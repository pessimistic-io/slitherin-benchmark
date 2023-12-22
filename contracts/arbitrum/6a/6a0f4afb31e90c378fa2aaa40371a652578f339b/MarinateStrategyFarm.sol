// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//                                                                            //
//                              #@@@@@@@@@@@@&,                               //
//                      .@@@@@   .@@@@@@@@@@@@@@@@@@@*                        //
//                  %@@@,    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@                    //
//               @@@@     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                 //
//             @@@@     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@               //
//           *@@@#    .@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@             //
//          *@@@%    &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            //
//          @@@@     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           //
//          @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           //
//                                                                            //
//          (@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@,           //
//          (@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@,           //
//                                                                            //
//          @@@@@   @@@@@@@@@   @@@@@@@@@   @@@@@@@@@   @@@@@@@@@             //
//            &@@@@@@@    #@@@@@@@.   ,@@@@@@@,   .@@@@@@@/    @@@@           //
//                                                                            //
//          @@@@@      @@@%    *@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           //
//          @@@@@      @@@@    %@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           //
//          .@@@@      @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            //
//            @@@@@  &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@             //
//                (&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&(                 //
//                                                                            //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

// Libraries
import { AccessControl } from "./AccessControl.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";

// Interfaces
import { IERC20 } from "./IERC20.sol";

/// @title Umami Marinate Auto-compounder Farm
contract MarinateStrategyFarm is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /************************************************
     *  STORAGE
     ***********************************************/

    /// @notice the total tokens staked
    uint256 public totalStaked = 0;

    /// @notice the withdrawal fee
    uint256 public WITHDRAW_FEE_BIPS;

    /// @notice the fee divisor
    uint256 public BIPS_DIVISOR;

    /// @notice scale used for fractional rewards
    uint256 public SCALE = 1e40;

    /// @notice the lock levels for staking
    uint32 lockDuration;

    /// @notice the period in seconds a fee applies after deposit
    uint256 public feePeriod;

    /// @notice allow early unlocking
    bool public allowEarlyUnlock;

    /// @notice the destination address of fees
    address feeDestination;

    /// @notice the autocompounder share token
    address public immutable STOKEN;

    /// @notice info on the farmer
    mapping(address => Farmer) public farmerInfo;

    /// @notice the amount to be paid to the user per token
    mapping(address => mapping(address => uint256)) public toBePaid;

    /// @notice total rewards allocated per reward token
    mapping(address => uint256) public totalTokenRewardsPerStake;

    /// @notice pair token rewards per user
    mapping(address => mapping(address => uint256)) public paidTokenRewardsPerStake;

    /// @notice the staked balance of a user
    mapping(address => uint256) public stakedBalance;

    /// @notice if the token reward is approved
    mapping(address => bool) public isApprovedRewardToken;

    /// @notice the tokens to issue rewards in
    address[] public rewardTokens;

    /************************************************
     *  CONSTANTS
     ***********************************************/

    /// @notice the autocompounder share token
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /************************************************
     *  STRUCTS
     ***********************************************/

    struct Farmer {
        uint256 lastDepositTime;
        uint256 amount;
        uint32 unlockTime;
    }

    /************************************************
     *  EVENTS
     ***********************************************/

    event Stake(uint256 lockDuration, address addr, uint256 amount);
    event Withdraw(address addr, uint256 amount);
    event RewardCollection(address token, address addr, uint256 amount);
    event RewardAdded(address token, uint256 amount, uint256 rps);

    /************************************************
     *  CONSTRUCTOR
     ***********************************************/

    constructor(
        address _STOKEN,
        address _feeDestination,
        uint32 _lockDuration
    ) {
        STOKEN = _STOKEN;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        feePeriod = 12 weeks;
        WITHDRAW_FEE_BIPS = 300;
        BIPS_DIVISOR = 10000;
        feeDestination = _feeDestination;
        lockDuration = _lockDuration;
        allowEarlyUnlock = false;
    }

    /************************************************
     *  DEPOSIT & WITHDRAW
     ***********************************************/

    /**
     * @notice stake autocompounder share tokens
     * @param amount the amount of umami to stake
     */
    function stake(uint256 amount) external {
        stakeFor(msg.sender, amount);
    }

    /**
     * @notice stake autocompounder share tokens for a user
     * @param user the user to stake for
     * @param amount the amount of umami to stake
     */
    function stakeFor(address user, uint256 amount) public {
        require(amount > 0, "Invalid stake amount");

        IERC20(STOKEN).safeTransferFrom(user, address(this), amount);

        // Store the sender's info
        Farmer memory info = farmerInfo[user];
        farmerInfo[user] = Farmer({
            lastDepositTime: block.timestamp,
            amount: info.amount + amount,
            unlockTime: uint32(block.timestamp + lockDuration)
        });

        if (stakedBalance[user] == 0) {
            // New user - not eligible for any previous rewards on any token
            for (uint256 i = 0; i < rewardTokens.length; i++) {
                address token = rewardTokens[i];
                paidTokenRewardsPerStake[token][user] = totalTokenRewardsPerStake[token];
            }
        } else {
            _collectRewards(user);
        }
        totalStaked += amount;
        stakedBalance[user] += amount;
        emit Stake(lockDuration, user, amount);
    }

    /**
     * @notice withdraw staked share tokens
     */
    function withdraw() public nonReentrant {
        require(farmerInfo[msg.sender].lastDepositTime != 0, "Haven't staked");
        require(allowEarlyUnlock || block.timestamp >= farmerInfo[msg.sender].unlockTime, "Too soon");

        _collectRewards(msg.sender);
        _payRewards(msg.sender);

        Farmer memory info = farmerInfo[msg.sender];
        delete farmerInfo[msg.sender];
        totalStaked -= info.amount;
        stakedBalance[msg.sender] = 0;

        uint256 withdrawFee = 0;

        if (block.timestamp <= info.lastDepositTime + feePeriod) {
            withdrawFee = (info.amount * WITHDRAW_FEE_BIPS) / BIPS_DIVISOR;
            require(IERC20(STOKEN).transfer(feeDestination, withdrawFee), "withdraw fee transfer failed");
        }

        IERC20(STOKEN).safeTransfer(msg.sender, info.amount - withdrawFee);

        emit Withdraw(msg.sender, info.amount - withdrawFee);
    }

    /************************************************
     *  REWARDS
     ***********************************************/

    /**
     * @notice claim rewards
     */
    function claimRewards() public nonReentrant {
        _collectRewards(msg.sender);
        _payRewards(msg.sender);
    }

    /**
     * @notice adds a reward token amount
     * @param token the token address of the reward
     * @param amount the amount of the token
     */
    function addReward(address token, uint256 amount) external nonReentrant {
        require(isApprovedRewardToken[token], "Token not approved for rewards");
        require(totalStaked > 0, "Total staked is zero");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        uint256 rewardPerStake = (amount * SCALE) / totalStaked;
        require(rewardPerStake > 0, "insufficient reward per stake");
        totalTokenRewardsPerStake[token] += rewardPerStake;
        emit RewardAdded(token, amount, rewardPerStake);
    }

    /**
     * @notice pay rewards to a marinator
     * @param user the user
     */
    function _payRewards(address user) private {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 amount = toBePaid[token][user];
            if (amount > 0) {
                IERC20(token).safeTransfer(user, amount);
                delete toBePaid[token][user];
            }
        }
    }

    /**
     * @notice collect rewards for a farmer
     * @param user the amount of umami to stake
     */
    function _collectRewards(address user) private {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            _collectRewardsForToken(rewardTokens[i], user);
        }
    }

    /**
     * @notice collect available token rewards
     * @param token the token to collect for
     * @param user the staker
     */
    function _collectRewardsForToken(address token, address user) private {
        uint256 balance = stakedBalance[user];
        if (balance > 0) {
            uint256 owedPerUnitStake = totalTokenRewardsPerStake[token] - paidTokenRewardsPerStake[token][user];
            uint256 totalRewards = (balance * owedPerUnitStake) / SCALE;
            paidTokenRewardsPerStake[token][user] = totalTokenRewardsPerStake[token];
            toBePaid[token][user] += totalRewards;
        }
    }

    /************************************************
     *  VIEWS
     ***********************************************/

    /**
     * @notice get the available token rewards
     * @param staker the farmer
     * @param token the token to check for
     * @return totalRewards - the available rewards for that token and farmer
     */
    function getAvailableTokenRewards(address staker, address token) external view returns (uint256 totalRewards) {
        uint256 owedPerUnitStake = totalTokenRewardsPerStake[token] - paidTokenRewardsPerStake[token][staker];
        uint256 pendingRewards = (stakedBalance[staker] * owedPerUnitStake) / SCALE;
        totalRewards = pendingRewards + toBePaid[token][staker];
    }

    /************************************************
     *  MUTATORS
     ***********************************************/

    /**
     * @notice set the lock level
     * @param _lockDurationInSeconds the duration in seconds
     */
    function setLockDuration(uint32 _lockDurationInSeconds) external onlyAdmin {
        require(_lockDurationInSeconds <= 52 weeks, "Too long");
        lockDuration = _lockDurationInSeconds;
    }

    /**
     * @notice set the fee period
     * @param _feePeriod the duration of the fee period in seconds
     */
    function setFeePeriod(uint256 _feePeriod) external onlyAdmin {
        require(_feePeriod <= 52 weeks, "Too long");
        feePeriod = _feePeriod;
    }

    /**
     * @notice set the fee destination
     * @param _feeDestination the new fee destination
     */
    function setFeeDestination(address _feeDestination) external onlyAdmin {
        require(_feeDestination != address(0), "invalid fee address");
        feeDestination = _feeDestination;
    }

    /**
     * @notice set the withdrawal fee
     * @param _fee the new withdrawal fee
     */
    function setWithdrawalFee(uint256 _fee) external onlyAdmin {
        require(_fee <= BIPS_DIVISOR, "admin fee too high");
        WITHDRAW_FEE_BIPS = _fee;
    }

    /**
     * @notice set the scale
     * @param _scale scale
     */
    function setScale(uint256 _scale) external onlyAdmin {
        SCALE = _scale;
    }

    /**
     * @notice add an approved reward token to be paid
     * @param token the address of the token to be paid in
     */
    function addApprovedRewardToken(address token) external onlyAdmin {
        require(!isApprovedRewardToken[token], "Reward token exists");
        isApprovedRewardToken[token] = true;
        rewardTokens.push(token);
    }

    /**
     * @notice remove a reward token
     * @param token the address of the token to remove
     */
    function removeApprovedRewardToken(address token) external onlyAdmin {
        require(isApprovedRewardToken[token], "Reward token does not exist");
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (rewardTokens[i] == token) {
                rewardTokens[i] = rewardTokens[rewardTokens.length - 1];
                rewardTokens.pop();
                isApprovedRewardToken[token] = false;
            }
        }
    }

    /**
     * @notice change early unlock
     * @param _earlyUnlock the duration in seconds
     */
    function setAllowEarlyUnlock(bool _earlyUnlock) external onlyAdmin {
        allowEarlyUnlock = _earlyUnlock;
    }

    /************************************************
     *  ADMIN
     ***********************************************/

    /**
     * @notice migrate a token to a different address
     * @param token the token address
     * @param destination the token destination
     * @param amount the token amount
     */
    function migrateToken(
        address token,
        address destination,
        uint256 amount
    ) external onlyAdmin {
        uint256 total = 0;
        if (amount == 0) {
            total = IERC20(token).balanceOf(address(this));
        } else {
            total = amount;
        }
        IERC20(token).safeTransfer(destination, total);
    }

    /**
     * @notice recover eth
     */
    function recoverEth() external onlyAdmin {
        // For recovering eth mistakenly sent to the contract
        (bool success, ) = msg.sender.call{ value: address(this).balance }("");
        require(success, "Withdraw failed");
    }

    /**
     * @dev Throws if not admin role
     */
    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not an admin");
        _;
    }
}

