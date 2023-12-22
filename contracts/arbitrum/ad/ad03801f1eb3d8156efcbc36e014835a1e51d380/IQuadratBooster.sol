// SPDX-License-Identifier: BUSL-1.1

/***
 *      ______             _______   __
 *     /      \           |       \ |  \
 *    |  $$$$$$\ __    __ | $$$$$$$\| $$  ______    _______  ______ ____    ______
 *    | $$$\| $$|  \  /  \| $$__/ $$| $$ |      \  /       \|      \    \  |      \
 *    | $$$$\ $$ \$$\/  $$| $$    $$| $$  \$$$$$$\|  $$$$$$$| $$$$$$\$$$$\  \$$$$$$\
 *    | $$\$$\$$  >$$  $$ | $$$$$$$ | $$ /      $$ \$$    \ | $$ | $$ | $$ /      $$
 *    | $$_\$$$$ /  $$$$\ | $$      | $$|  $$$$$$$ _\$$$$$$\| $$ | $$ | $$|  $$$$$$$
 *     \$$  \$$$|  $$ \$$\| $$      | $$ \$$    $$|       $$| $$ | $$ | $$ \$$    $$
 *      \$$$$$$  \$$   \$$ \$$       \$$  \$$$$$$$ \$$$$$$$  \$$  \$$  \$$  \$$$$$$$
 *
 *
 *
 */

pragma solidity 0.8.13;

import {IERC20} from "./IERC20.sol";
import {BasePayload, InitializePayload} from "./SQuadratBooster.sol";

interface IQuadratBooster {
    /**
     * @dev Initializes Booster.
     * @param payload_ Payload in bytes
     */
    function initialize(bytes calldata payload_) external;

    /**
     * @dev Deposits user amount. Time locked optionally.
     * @param _amount to be staked
     * @param _timeLockBlocks The numbers of blocks to lock the deposit.
     * @notice [_timeLockBlocks] is restricted by contract owner settings.
     * Set _timeLockBlocks to zero for usual deposit.
     */
    function deposit(uint256 _amount, uint32 _timeLockBlocks) external;

    /**
     * @dev Withdraws user amount.
     * @notice If amount equal zero then the position will be closed
     * @param _amount to be withdrawn
     */
    function withdraw(uint256 _amount) external;

    /**
     * @dev Withdraws user reward.
     */
    function claimReward() external;

    /**
     * @dev Transfers user deposit.
     * @param to address
     */
    function transferDeposit(address to) external;

    /**
     * @dev Unload unlocked rewards to treasure.
     * @param token Token address
     * @param treasure Transfer address
     */
    function subReward(address token, address treasure) external;

    /**
     * @dev Updates fromBlock number.
     * @param blockNumber A new fromBlock number
     */
    function setFromBlock(uint64 blockNumber) external;

    /**
     * @dev Updates toBlock number.
     * @param blockNumber A new toBlock number
     */
    function setToBlock(uint64 blockNumber) external;

    /**
     * @dev Updates fromBlock & toBlock numbers.
     * @param _fromBlockNumber A new fromBlock number
     * @param _toBlockNumber A new toBlock number
     */
    function setFromToBlock(uint64 _fromBlockNumber, uint64 _toBlockNumber)
        external;

    /**
     * @dev Updates block bonus.
     * @param blockNumber A new bonus number
     * @param bonus Percent
     */
    function setBlockBonus(uint64 blockNumber, uint16 bonus) external;

    /**
     * @dev Sets minimal withdraw blocks.
     * @param blocks The number of blocks
     */
    function setMinimalWithdrawBlocks(uint64 blocks) external;

    /**
     * @dev Sets minimal deposit amount blocks.
     * @param amount The amount
     */
    function setMinimalDepositAmount(uint256 amount) external;

    /**
     * @dev Sets timed deposit bonuses.
     * @param blocks The numbers of blocks for time lock
     * @param bonuses The bonus percents
     * @notice Set to zero to clear prev timed bonus and add new one
     */
    function setTimedBonus(uint32[] calldata blocks, uint16[] calldata bonuses)
        external;

    /**
     * @dev Updates reward per a block after funds transfer.
     */
    function updateReward() external;

    /**
     * @dev Updates cumulative reward by current block.
     * @param byBlock By block nubmer
     * @return _cumulativeRewardPerShare A new cumulativeRewardPerShare
     */
    function updateCumulativeRewardByBlock(uint64 byBlock)
        external
        returns (uint256 _cumulativeRewardPerShare);

    /**
     * @dev Updates cumulative reward by current block.
     * @return _cumulativeRewardPerShare A new cumulativeRewardPerShare
     */
    function updateCumulativeReward()
        external
        returns (uint256 _cumulativeRewardPerShare);

    /**
     * @dev Returns deposit token address
     */
    function depositToken() external view returns (IERC20);

    /**
     * @dev Returns `from` block number
     */
    function fromBlock() external view returns (uint64);

    /**
     * @dev Returns reward token address
     */
    function rewardToken() external view returns (IERC20);

    /**
     * @dev Returns `to` block number
     */
    function toBlock() external view returns (uint64);

    /**
     * @dev Returns Total block reward amount
     */
    function rewardPerBlock() external view returns (uint256);

    /**
     * @dev Returns Total reward amount already claimed
     */
    function rewardClaimed() external view returns (uint256);

    /**
     * @dev Returns Total deposit amount
     */
    function totalDeposit() external view returns (uint256);

    /**
     * @dev Returns virtual total deposit amount
     */
    function virtualTotalDeposit() external view returns (uint256);

    /**
     * @dev Current cumulative rewardPerShare * MULTIPLIER
     */
    function cumulativeRewardPerShare() external view returns (uint256);

    /**
     * @dev Current cumulative blockNumber
     */
    function cumulativeRewardBlockNumber() external view returns (uint64);

    /**
     * @dev Minimal block numbers for staking
     */
    function minimalWithdrawBlocks() external view returns (uint64);

    /**
     * @dev Minimal deposit value for staking
     */
    function minimalDepositAmount() external view returns (uint256);

    /**
     * @dev Timed deposit bonus
     */
    function timedBonus(uint32 blocks) external view returns (uint16);

    /**
     * @dev Booster factory address
     */
    function factory() external view returns (address);

    /**
     * @dev Info of each user that stakes token
     */
    function deposits(address user)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint64
        );

    /**
     * @dev Historical Cumulative Reward Per Shares * MULTIPLIER
     */
    function cumulativeRewardPerShares(uint64 block)
        external
        view
        returns (uint256);

    /**
     * @dev Returns rewardPerBlock, rewardClaimed, rewardLocked, rewardUnlocked
     * @return (rewardPerBlock, rewardClaimed, rewardLocked, rewardUnlocked)
     */
    function totalReward()
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        );

    /**
     * @dev Returns cumulative reward per share amount, block number for it's calculation and total cumulative reward
     * @return (cumulativeRewardPerShare, cumulativeRewardBlockNumber, cumulativeReward)
     */
    function cumulativeReward()
        external
        view
        returns (
            uint256,
            uint64,
            uint256
        );

    /**
     * @dev Returns block bonus information
     * @return (bonusBlockNumber, blockBonus)
     */
    function blockBonus() external view returns (uint64, uint256);

    /**
     * @dev Returns Pending & Expired time lock deposit blocks.
     */
    function timeLockDepositBlocks() external view returns (uint256, uint256);

    /**
     * @dev Gets contract attributes.
     * @return payload A contract attribute structure and booster address
     */
    function viewAttributes()
        external
        view
        returns (InitializePayload memory payload, address booster);

    /**
     * @dev Transforms payload struct to bytes array to pass it to factory.
     * @param payload InitializePayload data
     * @return bytes array
     */
    function transformPayloadToBytes(InitializePayload calldata payload)
        external
        pure
        returns (bytes memory);

    /**
     * @dev Transforms bytes array to base payload struct.
     * @param data bytes array
     * @return payload BasePayload data
     */
    function transformBytesToBasePayload(bytes calldata data)
        external
        pure
        returns (BasePayload memory payload);

    /**
     * @dev Calculates cumulative reward per share without time lock deposits.
     * @return _cumulativeRewardPerShare Updated cumulative reward per share
     */
    function calculateCumulativeReward()
        external
        view
        returns (uint256 _cumulativeRewardPerShare);

    /**
     * @dev Returns depositor number.
     * @return Depositor amount
     */
    function depositorNum() external view returns (uint256);

    /**
     * @dev Returns depositor addresses.
     * @return Depositors collection
     */
    function depositors() external view returns (address[] memory);

    /**
     * @dev Calculates user reward.
     * @param user address
     * @return _rewardAmount
     */
    function userReward(address user) external view returns (uint256);

    event DepositTrasfered(address indexed, address indexed, uint256);
    event RewardAdded(address indexed, address indexed, uint256);
    event RewardSubed(
        address indexed,
        address indexed,
        address indexed,
        uint256
    );
    event FromBlockUpdated(address indexed, uint64);
    event ToBlockUpdated(address indexed, uint64);
    event FromToBlockUpdated(address indexed, uint64, uint64);
    event BlockBonusUpdated(address indexed, uint64, uint16);
    event TimedBonusUpdated(address indexed, uint32[], uint16[]);
    event MinimalWithdrawBlocksUpdated(address indexed, uint64);
    event MinimalDepositAmountUpdated(address indexed, uint256);
    event RewardUpdated(address indexed, uint256, uint256);
    event Deposit(address indexed, uint256, uint256, uint256);
    event Withdraw(address indexed, uint256, uint256);
    event ClaimReward(address indexed, uint256);
}

