// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;
pragma abicoder v2;

import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";

contract CruizeLGE is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    struct UserInfo {
        uint256 allocation; // amount taken into account to obtain the tokens (amount spent)
        uint256 contribution; // amount spent to buy tokens in the LGE
        bool hasClaimed; // has already claimed its allocation
    }

    IERC20 public immutable CRUIZE; // CRUIZE contract
    IERC20 public immutable ARMADA; // ARMADA contract (eg. vested tokens)
    IERC20 public immutable USDC;

    uint256 public immutable START_TIME = 1682341200;
    uint256 public immutable END_TIME;

    mapping(address => UserInfo) public userInfo; // buyers info
    mapping(uint => uint) private uniqueCodeStorage;
    uint256 public totalRaised; // raised amount
    uint256 public totalAllocation;

    uint256 public immutable MAX_CRUIZE_TO_DISTRIBUTE; // max CRUIZE amount to distribute during the sale
    uint256 public immutable MAX_ARMADA_TO_DISTRIBUTE; // max ARMADA amount to distribute during the sale
    uint256 public immutable MIN_TOTAL_RAISED_FOR_MAX_ALLOC; // amount to reach to distribute max CRUIZE amount

    uint256 public immutable MAX_RAISE_AMOUNT;

    address public immutable escrow; // cruizeEscrow contract, will receive the raised amount

    bool public unsoldTokensWithdrew;

    bool public forceClaimable; // safety measure to ensure that we can force claimable to true in case awaited LP token address plan changes during the LGE

    constructor(
        address cruize,
        address armada,
        address usdcAddress,
        address _escrow
    ) {
        require(_escrow != address(0), "escrow cannot be the zero address");
        require(
            cruize != address(0) && armada != address(0),
            "CRUIZE and ARMADA cannot be the zero address"
        );

        CRUIZE = IERC20(cruize);
        ARMADA = IERC20(armada);
        USDC = IERC20(usdcAddress);
        escrow = _escrow;
        (MAX_CRUIZE_TO_DISTRIBUTE, MAX_ARMADA_TO_DISTRIBUTE) = (
            10_000_000 * 1e18,
            10_000_000 * 1e18
        );
        MAX_RAISE_AMOUNT = 5_000_000 * 1e6; //Since USDC, it's 6 decimal places so 1e6
        MIN_TOTAL_RAISED_FOR_MAX_ALLOC = MAX_RAISE_AMOUNT; // Max allocation is max raise amount
        END_TIME = START_TIME + 1 weeks; //LGE for CRUIZE will last From April 24 -> May 1
    }

    /********************************************/
    /****************** EVENTS ******************/
    /********************************************/

    event Buy(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount, uint256 amount2);
    event EmergencyWithdraw(address token, uint256 amount);
    event uniqueCodeIteration(uint code, uint amount);

    /***********************************************/
    /****************** MODIFIERS ******************/
    /***********************************************/

    /**
     * @dev Check whether the sale is currently active
     *
     * Will be marked as inactive if CRUIZE & ARMADA have not been deposited into the contract
     */
    modifier isSaleActive() {
        require(hasStarted() && !hasEnded(), "Sale is not yet open");
        require(
            CRUIZE.balanceOf(address(this)) >= MAX_CRUIZE_TO_DISTRIBUTE,
            "CRUIZE has not been added to the contract in full yet"
        );
        require(
            ARMADA.balanceOf(address(this)) >= MAX_ARMADA_TO_DISTRIBUTE,
            "ARMADA has not been added to the contract in full yet"
        );
        _;
    }

    /**
     * @dev Check whether users can claim their purchased CRUIZE and ARMADA
     *
     */
    modifier isClaimable() {
        require(hasEnded(), "The LGE has not ended yet");
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
        return END_TIME.sub(_currentBlockTimestamp());
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
     * @dev Returns the amount of CRUIZE to be distributed based on the current total raised
     */
    function cruizeToDistribute() public view returns (uint256) {
        if (MIN_TOTAL_RAISED_FOR_MAX_ALLOC > totalRaised) {
            return
                MAX_CRUIZE_TO_DISTRIBUTE.mul(totalRaised).div(
                    MIN_TOTAL_RAISED_FOR_MAX_ALLOC
                );
        }
        return MAX_CRUIZE_TO_DISTRIBUTE;
    }

    /**
     * @dev Returns the amount of ARMADA to be distributed based on the current total raised
     */
    function armadaToDistribute() public view returns (uint256) {
        if (MIN_TOTAL_RAISED_FOR_MAX_ALLOC > totalRaised) {
            return
                MAX_ARMADA_TO_DISTRIBUTE.mul(totalRaised).div(
                    MIN_TOTAL_RAISED_FOR_MAX_ALLOC
                );
        }
        return MAX_ARMADA_TO_DISTRIBUTE;
    }

    /**
     * @dev Returns the amount of CRUIZE + ARMADA to be distributed based on the current total raised
     */
    function tokensToDistribute() public view returns (uint256) {
        return cruizeToDistribute().add(armadaToDistribute());
    }

    /// @dev gather the amount of USDC (1e6) raised per uniqueCode
    function getUniqueCodeRaise(uint _uniqueCode) public view returns (uint) {
        return (uniqueCodeStorage[_uniqueCode]);
    }

    /**
     * @dev Get user tokens amount to claim
     */
    function getExpectedClaimAmount(
        address account
    ) public view returns (uint256 cruizeAmount, uint256 armadaAmount) {
        if (totalAllocation == 0) return (0, 0);

        UserInfo memory user = userInfo[account];
        cruizeAmount = (
            user.allocation.mul(cruizeToDistribute()).div(totalAllocation)
        );
        // 50/50 split so they are equal amounts
        return (cruizeAmount, cruizeAmount);
    }

    /****************************************************************/
    /****************** EXTERNAL PUBLIC FUNCTIONS  ******************/
    /****************************************************************/

    /**
     * @dev Purchase an allocation for the sale for a value of USDC
     */
    function buy(
        uint256 amount,
        uint _uniqueCode
    ) external isSaleActive nonReentrant {
        USDC.safeTransferFrom(msg.sender, address(this), amount);
        _buy(amount);
        // uniqueCode will be mapped and iterated upon per purchase.
        // At the end of the LGE we can see how much USDC was brought in per referee and give them compensation
        if (_uniqueCode != 0) {
            uniqueCodeStorage[_uniqueCode] += amount;
            emit uniqueCodeIteration(_uniqueCode, amount);
        }
    }

    function _buy(uint256 amount) internal {
        require(amount > 0, "cannot buy a zero amount of CRUIZE/ARMADA");
        require(
            totalRaised.add(amount) <= MAX_RAISE_AMOUNT,
            "The hardcap of 5_000_000 USDC has been reached!"
        );
        require(
            !address(msg.sender).isContract() &&
                !address(tx.origin).isContract(),
            "You cannot interact as a contract, please use an EOA"
        );

        UserInfo storage user = userInfo[msg.sender];

        uint256 allocation = amount;

        // update raised amounts
        user.contribution = user.contribution.add(amount);
        totalRaised = totalRaised.add(amount);

        // update allocations
        user.allocation = user.allocation.add(allocation);
        totalAllocation = totalAllocation.add(allocation);

        emit Buy(msg.sender, amount);
        // transfer contribution to cruizeEscrow
        USDC.safeTransfer(escrow, amount);
    }

    /**
     * USERS Claim full purchased CRUIZE & ARMADA during the sale
     */
    function claim_CRUZE_And_ARMADA_Allocations() external isClaimable {
        UserInfo storage user = userInfo[msg.sender];

        require(
            totalAllocation > 0 && user.allocation > 0,
            "you do not have any allocation to claim!"
        );
        require(!user.hasClaimed, "Your allocation has been already claimed");
        user.hasClaimed = true;

        (uint256 token1Amount, uint256 token2Amount) = getExpectedClaimAmount(
            msg.sender
        );

        emit Claim(msg.sender, token1Amount, token2Amount);

        if (token1Amount > 0) {
            // send CRUIZE allocation
            _safeClaimTransfer(CRUIZE, msg.sender, token1Amount);
        }
        if (token2Amount > 0) {
            // send ARMADA allocation
            _safeClaimTransfer(ARMADA, msg.sender, token2Amount);
        }
    }

    /****************************************************************/
    /********************** OWNABLE FUNCTIONS  **********************/
    /****************************************************************/

    /**
     * @dev Withdraw unsold CRUIZE + ARMADA if MIN_TOTAL_RAISED_FOR_MAX_ALLOC has not been reached
     *
     * Must only be called by the owner
     */
    function withdrawUnsoldTokens() external onlyOwner {
        require(hasEnded(), "The LGE has not yet ended");
        require(
            !unsoldTokensWithdrew,
            "The unallocated tokens have been already withdrawn"
        );

        uint256 totalTokenSold = cruizeToDistribute();
        uint256 totalToken2Sold = armadaToDistribute();

        unsoldTokensWithdrew = true;
        if (totalTokenSold > 0)
            CRUIZE.transfer(
                msg.sender,
                MAX_CRUIZE_TO_DISTRIBUTE.sub(totalTokenSold)
            );
        if (totalToken2Sold > 0)
            ARMADA.transfer(
                msg.sender,
                MAX_ARMADA_TO_DISTRIBUTE.sub(totalToken2Sold)
            );
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

