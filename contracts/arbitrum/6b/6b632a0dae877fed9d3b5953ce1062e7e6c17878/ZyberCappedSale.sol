// SPDX-License-Identifier: MIT
pragma solidity =0.8.18;
pragma abicoder v2;

import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./IWETH.sol";
import "./IVaultUtils.sol";

contract ZyberCappedSale is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;

    struct UserInfo {
        uint256 allocation; // amount taken into account to obtain TOKEN (amount spent + discount)
        uint256 contribution; // amount spent to buy TOKEN
        bool hasClaimed; // has already claimed its allocation
    }

    IERC20 public immutable SALE_TOKEN; // token used to participate
    //   IERC20 public immutable LP_TOKEN; // Project LP address

    IERC20 public immutable PROJECT_TOKEN; // Project LP address

    uint256 public immutable START_TIME; // sale start time
    uint256 public immutable END_TIME; // sale end time

    uint256 public constant REFERRAL_SHARE = 3; // 3%

    mapping(address => UserInfo) public userInfo; // buyers and referrers info
    uint256 public totalRaised; // raised amount, does not take into account referral shares
    uint256 public totalAllocation; // takes into account discounts

    uint256 public immutable MAX_PROJECT_TOKENS_TO_DISTRIBUTE; // max PROJECT_TOKEN amount to distribute during the sale
    uint256 public immutable MIN_TOTAL_RAISED_FOR_MAX_PROJECT_TOKEN; // amount to reach to distribute max PROJECT_TOKEN amount

    uint256 public immutable MAX_RAISE_AMOUNT;
    uint256 public CAP_PER_WALLET;

    address public immutable treasury; // treasury multisig, will receive raised amount

    bool public unsoldTokensBurnt;

    bool public forceClaimable; // safety measure to ensure that we can force claimable to true in case awaited LP token address plan change during the sale

    bool public hardCapReached;

    bool public noLimits;

    address public constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    IVaultUtils public immutable vaultUtils;

    struct Vester {
        uint256 withdrawnAmount;
        uint256 tokensPerDay;
    }
    mapping(address => Vester) public vesters;

    constructor(
        IERC20 saleToken,
        IERC20 projectToken,
        IVaultUtils _vaultUtils,
        uint256 startTime,
        uint256 endTime,
        address treasury_,
        uint256 maxToDistribute,
        uint256 minToRaise,
        uint256 maxToRaise,
        uint256 capPerWallet
    ) {
        require(startTime < endTime, "invalid dates");
        require(treasury_ != address(0), "invalid treasury");

        SALE_TOKEN = saleToken;
        //  LP_TOKEN = lpToken;
        START_TIME = startTime;
        END_TIME = endTime;
        treasury = treasury_;
        MAX_PROJECT_TOKENS_TO_DISTRIBUTE = maxToDistribute;
        MIN_TOTAL_RAISED_FOR_MAX_PROJECT_TOKEN = minToRaise;
        if (maxToRaise == 0) {
            maxToRaise = type(uint256).max;
        }
        MAX_RAISE_AMOUNT = maxToRaise;
        if (capPerWallet == 0) {
            capPerWallet = type(uint256).max;
        }
        CAP_PER_WALLET = capPerWallet;
        vaultUtils = _vaultUtils;
        PROJECT_TOKEN = projectToken;
    }

    /********************************************/
    /****************** EVENTS ******************/
    /********************************************/

    event Buy(address indexed user, uint256 amount);
    event ClaimRefEarnings(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);
    event NewRefEarning(address referrer, uint256 amount);
    event DiscountUpdated();
    event EmergencyWithdraw(address token, uint256 amount);

    /***********************************************/
    /****************** MODIFIERS ******************/
    /***********************************************/

    //  receive() external payable() {
    //    require(address(saleToken) == weth, "non ETH sale");
    //  }

    /**
     * @dev Check whether the sale is currently active
     *
     * Will be marked as inactive if PROJECT_TOKEN has not been deposited into the contract
     */
    modifier isSaleActive() {
        require(hasStarted() && !hasEnded(), "isActive: sale is not active");
        _;
    }

    /**
     * @dev Check whether users can claim their purchased PROJECT_TOKEN
     *
     * Sale must have ended, and LP tokens must have been formed
     */
    modifier isClaimable() {
        require(hasEnded(), "isClaimable: sale has not ended");
        require(forceClaimable, "isClaimable: no LP tokens");
        _;
    }

    /**************************************************/
    /****************** PUBLIC VIEWS ******************/
    /**************************************************/

    /**
     * @dev Get remaining duration before the end of the sale
     */
    function getRemainingTime() external view returns (uint256) {
        if (hasEnded()) return 0;
        return END_TIME - _currentBlockTimestamp();
    }

    /**
     * @dev Returns whether the sale has already started
     */
    function hasStarted() public view returns (bool) {
        return _currentBlockTimestamp() >= START_TIME;
    }

    /**
     * @dev Returns whether the sale has already ended
     */
    function hasEnded() public view returns (bool) {
        return END_TIME <= _currentBlockTimestamp();
    }

    /**
     * @dev Returns the amount of PROJECT_TOKEN to be distributed based on the current total raised
     */
    function tokensToDistribute() public view returns (uint256) {
        if (MIN_TOTAL_RAISED_FOR_MAX_PROJECT_TOKEN > totalRaised) {
            return
                (MAX_PROJECT_TOKENS_TO_DISTRIBUTE * totalRaised) /
                MIN_TOTAL_RAISED_FOR_MAX_PROJECT_TOKEN;
        }
        return MAX_PROJECT_TOKENS_TO_DISTRIBUTE;
    }

    /**
     * @dev Get user share times 1e5
     */
    function getExpectedClaimAmount(
        address account
    ) public view returns (uint256) {
        if (totalAllocation == 0) return 0;

        UserInfo memory user = userInfo[account];
        return (user.allocation * tokensToDistribute()) / totalAllocation;
    }

    function getExpectedAllocation(
        address account
    ) external view returns (uint256 userMaxCap) {
        if (noLimits) {
            userMaxCap = type(uint256).max;
        } else {
            userMaxCap = CAP_PER_WALLET * vaultUtils.getVaultUserInfo(account);
        }
    }

    function getMultiplier(
        address account
    ) external view returns (uint256 multiplier) {
        multiplier = vaultUtils.getVaultUserInfo(account);
    }

    /****************************************************************/
    /****************** EXTERNAL PUBLIC FUNCTIONS  ******************/
    /****************************************************************/

    function buyETH() external payable isSaleActive nonReentrant {
        require(address(SALE_TOKEN) == weth, "non ETH sale");
        uint256 amount = msg.value;
        IWETH(weth).deposit{value: amount}();
        _buy(msg.sender, amount);
    }

    /**
     * @dev Purchase an allocation for the sale for a value of "amount" SALE_TOKEN, referred by "referralAddress"
     */
    function buy(
        address _user,
        uint256 amount
    ) external isSaleActive nonReentrant {
        _buy(_user, amount);
    }

    function _buy(address _user, uint256 amount) internal {
        require(amount > 0, "buy: zero amount");
        require(!hardCapReached, "buy: hardcap reached");
        if (totalRaised + amount >= MAX_RAISE_AMOUNT) {
            amount = MAX_RAISE_AMOUNT - totalRaised;
            hardCapReached = true;
        }
        /*require(
            !address(msg.sender).isContract() &&
                !address(tx.origin).isContract(),
            "FORBIDDEN"
        );*/

        uint256 participationAmount = amount;
        UserInfo storage user = userInfo[_user];
        uint256 userMaxCap;
        if (noLimits) {
            userMaxCap = type(uint256).max;
        } else {
            userMaxCap = CAP_PER_WALLET * vaultUtils.getVaultUserInfo(_user);
        }
        require(
            user.contribution + amount <= userMaxCap,
            "buy: wallet cap reached"
        );

        uint256 allocation = amount;

        // update raised amounts
        user.contribution = user.contribution + amount;
        totalRaised = totalRaised + amount;

        // update allocations
        user.allocation = user.allocation + allocation;
        totalAllocation = totalAllocation + allocation;

        emit Buy(_user, participationAmount);
        // transfer contribution to treasury
        SALE_TOKEN.safeTransferFrom(_user, treasury, participationAmount);
    }

    /**
     * @dev Claim purchased PROJECT_TOKEN during the sale
     */

    function claim() external isClaimable {
        UserInfo storage user = userInfo[msg.sender];

        require(
            totalAllocation > 0 && user.allocation > 0,
            "claim: zero allocation"
        );
        require(!user.hasClaimed, "claim: already claimed");
        user.hasClaimed = true;

        uint256 amount = getExpectedClaimAmount(msg.sender);

        emit Claim(msg.sender, amount);

        // send PROJECT_TOKEN allocation
        PROJECT_TOKEN.safeTransfer(msg.sender, amount);
    }

    /****************************************************************/
    /********************** OWNABLE FUNCTIONS  **********************/
    /****************************************************************/

    /********************************************************/
    /****************** /!\ EMERGENCY ONLY ******************/
    /********************************************************/

    /**
     * @dev Failsafe
     */
    function emergencyWithdrawFunds(
        address token,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).safeTransfer(msg.sender, amount);

        emit EmergencyWithdraw(token, amount);
    }

    function setForceClaimable() external onlyOwner {
        forceClaimable = true;
    }

    /********************************************************/
    /****************** INTERNAL FUNCTIONS ******************/
    /********************************************************/

    /**
     * @dev Utility function to get the current block timestamp
     */
    function _currentBlockTimestamp() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    /**
     * @dev set no limits to enable no cap for users
     */
    function toggleNoLimits() external onlyOwner {
        noLimits = !noLimits;
    }

    /**
     * @dev set cpa per wallet
     */
    function setCapPerwallet(uint256 _amount) external onlyOwner {
        CAP_PER_WALLET = _amount;
    }
}

