// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;
pragma abicoder v2;

import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";

contract RamsesLGEv2 is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    struct UserInfo {
        uint256 allocation; // amount taken into account to obtain the tokens (amount spent)
        uint256 contribution; // amount spent to participate tokens in the LGE
        bool hasClaimed; // has already claimed its allocation
        uint256 claimedAmount;
    }

    IERC20 public immutable UWU; // UWU contract
    IERC20 public immutable USDC; //collateral token

    address public immutable RAMSES_TREASURY;

    uint256 public immutable START_TIME;
    uint256 public end_time;

    mapping(address => UserInfo) public userInfo; // participaters info
    mapping(address => uint) private refStorage; //amount of money sent to each referee
    uint256 public totalRaised; // raised amount
    uint256 public totalAllocation;

    uint256 public immutable MAX_UWU_TO_DISTRIBUTE; // max UWU amount to distribute during the LGE
    uint256 public immutable SOFT_CAP; // amount to reach to distribute max UWU amount
    uint256 public immutable REF_CUT; // 0-5 0% - 5%
    uint256 public immutable HARD_CAP;
    uint256 public immutable VEST_LENGTH; // 12 * 30 * 24 * 60 * 60 for 12 month vest
    uint256 public immutable VEST_PERCENTAGE; // 40 for 40% vest

    string public token_name = "UWU";

    address public immutable escrow; // tokenEscrow contract, will receive the raised amount

    bool public unsoldTokensWithdrew;

    bool public forceClaimable; // safety measure to ensure that we can force claimable to true in case plan changes during the LGE

    constructor(
        address _uwu,
        address _usdcAddress,
        address _escrow,
        address _ramsesTreasury,
        uint _startTime,
        uint _seconds,
        uint _refCut,
        uint _vestLength,
        uint _vestPercentage
    ) {
        require(
            _escrow != address(0),
            "RAMSES LGE: The escrow cannot be the zero address"
        );
        require(
            _uwu != address(0),
            "RAMSES LGE: UWU cannot be the zero address"
        );

        require(
            _refCut >= 0 && _refCut <= 5, //RefCut between 0 and 5%
            "RAMSES LGE: The Referral cut is invalid!"
        ); //for UWU LGE this should be 3 for 3%

        UWU = IERC20(_uwu);
        USDC = IERC20(_usdcAddress);
        escrow = _escrow;
        RAMSES_TREASURY = _ramsesTreasury;
        MAX_UWU_TO_DISTRIBUTE = 1_500_000 * 1e18;
        REF_CUT = _refCut;
        HARD_CAP = 1_575_000 * 1e6; //Since USDC, it's 6 decimal places so 1e6
        SOFT_CAP = HARD_CAP;
        START_TIME = _startTime; //set the start time in unix timestamp
        end_time = START_TIME + _seconds; //LGE LENGTH, add seconds
        VEST_LENGTH = _vestLength;
        VEST_PERCENTAGE = _vestPercentage;
    }

    /********************************************/
    /****************** EVENTS ******************/
    /********************************************/

    event Participated(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);
    event EmergencyWithdraw(address token, uint256 amount);
    event RefCodeUsed(address _referrer, uint amount);
    event Extended(uint _extension);

    /***********************************************/
    /****************** MODIFIERS ******************/
    /***********************************************/

    /**
     * @dev Check whether the LGE is currently active
     *
     * Will be marked as inactive if UWU &  have not been deposited into the contract
     */
    modifier isLGEActive() {
        require(
            hasStarted() && !hasEnded(),
            "RAMSES LGE: The LGE is not yet open"
        );
        require(
            UWU.balanceOf(address(this)) >= MAX_UWU_TO_DISTRIBUTE,
            "RAMSES LGE: The token has not been added to the contract in full yet"
        );
        _;
    }

    /**
     * @dev Check whether users can claim their purchased UWU and
     *
     */
    modifier isClaimable() {
        require(hasEnded(), "RAMSES LGE: The LGE has not ended yet");
        _;
    }

    /**************************************************/
    /****************** PUBLIC VIEWS ******************/
    /**************************************************/

    /**
     * @dev Get remaining duration before the end of the LGE
     */
    function getRemainingTime() external view returns (uint256) {
        if (hasEnded()) return 0;
        return end_time.sub(_currentBlockTimestamp());
    }

    /**
     * @dev Returns whether the LGE has already started
     */
    function hasStarted() public view returns (bool) {
        return _currentBlockTimestamp() >= START_TIME;
    }

    /**
     * @dev Returns whether the LGE has already ended
     */
    function hasEnded() public view returns (bool) {
        return end_time <= _currentBlockTimestamp();
    }

    /**
     * @dev Returns the amount of UWU to be distributed based on the current total raised
     */
    function tokenToDistribute() public view returns (uint256) {
        if (SOFT_CAP > totalRaised) {
            return MAX_UWU_TO_DISTRIBUTE.mul(totalRaised).div(SOFT_CAP);
        }
        return MAX_UWU_TO_DISTRIBUTE;
    }

    /// @dev gather the amount of USDC (1e6) raised per uniqueCode
    function getRefferalRaised(address _referrer) public view returns (uint) {
        return (refStorage[_referrer]);
    }

    /**
     * @dev Get user tokens amount to claim
     */
    function getExpectedClaimAmount(
        address account
    ) public view returns (uint256 tokenAmount) {
        if (totalAllocation == 0) return (0);

        UserInfo memory user = userInfo[account];
        tokenAmount = (
            user.allocation.mul(tokenToDistribute()).div(totalAllocation)
        );
        return (tokenAmount);
    }

    /****************************************************************/
    /****************** EXTERNAL PUBLIC FUNCTIONS  ******************/
    /****************************************************************/

    /**
     * @dev Purchase an allocation for the LGE for a value of USDC
     */
    function participate(
        uint256 amount,
        address _referrer
    ) external isLGEActive nonReentrant {
        // protection against malicious referral harvesting
        if (
            _referrer == msg.sender ||
            _referrer == address(0) ||
            _referrer.isContract()
        ) {
            _referrer = RAMSES_TREASURY;
        }
        USDC.safeTransferFrom(msg.sender, address(this), amount);
        _participate(amount, _referrer);
        refStorage[_referrer] += amount;
        emit RefCodeUsed(_referrer, amount);

        // referral's storage will be mapped and iterated upon per purchase.
        // At the end of the LGE we can see how much collateral was brought in per referer
    }

    function _participate(uint256 amount, address _refer) internal {
        require(
            amount > 0,
            "RAMSES LGE: You cannot deposit a zero amount of collateral!"
        );
        require(
            totalRaised.add(amount) <= HARD_CAP,
            "RAMSES LGE: The hardcap has been reached!"
        );
        require(
            !address(msg.sender).isContract() &&
                !address(tx.origin).isContract(),
            "RAMSES LGE: You cannot interact as a contract, please use an EOA"
        );
        uint escrowedAmount;

        UserInfo storage user = userInfo[msg.sender];

        uint256 allocation = amount;

        // update raised amounts
        user.contribution = user.contribution.add(amount);
        totalRaised = totalRaised.add(amount);

        // update allocations
        user.allocation = user.allocation.add(allocation);
        totalAllocation = totalAllocation.add(allocation);

        emit Participated(msg.sender, amount);
        // transfer contribution to escrow
        escrowedAmount = amount - ((amount * REF_CUT) / 100); // ((amount * REF_CUT)/100) returns the % needed to send to referrals
        USDC.safeTransfer(escrow, escrowedAmount);
        USDC.safeTransfer(_refer, ((amount * REF_CUT) / 100));
    }

    /**
     * USERS Claim full allocation of UWU, After the LGE
     */
    function claim_Allocations() external isClaimable {
        UserInfo storage user = userInfo[msg.sender];

        require(
            totalAllocation > 0 && user.allocation > 0,
            "RAMSES LGE: You do not have any allocation to claim!"
        );
        require(
            !user.hasClaimed,
            "RAMSES LGE: Your allocation has been already claimed"
        );
        require(block.timestamp >= end_time + 86400, "RAMSES LGE: There is a 24 hour buffer to claim after the LGE has concluded");

        uint256 tokenAmount = getExpectedClaimAmount(msg.sender);

        uint256 unlockedAmount = tokenAmount;
        if (block.timestamp < end_time + VEST_LENGTH) {
            unlockedAmount =
                ((tokenAmount * (100 - VEST_PERCENTAGE)) / 100) +
                ((((tokenAmount * VEST_PERCENTAGE) / 100) *
                    (block.timestamp - end_time)) / VEST_LENGTH);
        } else {
            user.hasClaimed = true;
        }

        uint256 claimableAmount = unlockedAmount - user.claimedAmount;
        user.claimedAmount = unlockedAmount;

        emit Claim(msg.sender, claimableAmount);

        if (claimableAmount > 0) {
            // send UWU allocation
            _safeClaimTransfer(UWU, msg.sender, claimableAmount);
        }
    }

    /****************************************************************/
    /********************** OWNABLE FUNCTIONS  **********************/
    /****************************************************************/

    /**
     * @dev Withdraw unsold UWU +  if SOFT_CAP has not been reached
     *
     * Must only be called by the owner
     */
    function withdrawUnsoldTokens() external onlyOwner {
        require(hasEnded(), "RAMSES LGE: The LGE has not yet ended");
        require(
            !unsoldTokensWithdrew,
            "RAMSES LGE: The unallocated tokens have been already withdrawn"
        );

        uint256 totalTokenSold = tokenToDistribute();

        unsoldTokensWithdrew = true;
        if (totalTokenSold > 0)
            UWU.transfer(msg.sender, MAX_UWU_TO_DISTRIBUTE.sub(totalTokenSold));
    }

    /**  @dev extend the end_time time if there is a reason to **/
    function extend_end_time(uint _extensionSeconds) external onlyOwner {
        end_time += _extensionSeconds;
        emit Extended(_extensionSeconds);
    }

    /********************************************************/
    /****************** /!\ EMERGENCY ONLY ******************/
    /********************************************************/

    /**
     * @dev Failsafe incase of an emergency in the LGE
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
     * @dev Safe token transfer function, in case rounding error causes contract to not have enough tokens
     */
    function _safeClaimTransfer(
        IERC20 token,
        address to,
        uint256 amount
    ) internal {
        uint256 balance = token.balanceOf(address(this));
        bool transferSuccess = false;

        if (amount > balance) {
            transferSuccess = token.transfer(to, balance);
        } else {
            transferSuccess = token.transfer(to, amount);
        }

        require(transferSuccess, "safeClaimTransfer: Transfer failed");
    }

    /**
     * @dev Utility function to get the current block timestamp
     */
    function _currentBlockTimestamp() internal view virtual returns (uint256) {
        return block.timestamp;
    }
}

