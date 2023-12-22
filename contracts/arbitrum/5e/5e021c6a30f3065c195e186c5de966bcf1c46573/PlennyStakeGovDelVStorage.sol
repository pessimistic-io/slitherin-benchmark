// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./IPlennyLocking.sol";

/// @title  PlennyStakeGovDelVStorage
/// @notice Storage contract for PlennyStakeGovDelV
abstract contract PlennyStakeGovDelVStorage is IPlennyLocking {

    /// @notice weight multiplier
    uint256 public constant WEIGHT_MULTIPLIER = 100;

    /// @notice total plenny amount locked
    uint256 public totalValueLocked;
    /// @notice total votes locked
    uint256 public override totalVotesLocked;
    /// @notice total votes already collected
    uint256 public totalVotesCollected;

    /// @notice reward percentage
    uint256 public override govLockReward; // 0.01%
    /// @notice distribution period, in blocks
    uint256 public nextDistributionBlocks; // 1 day
    /// @notice blocks per week
    uint256 public averageBlocksPerWeek; // 1 week

    /// @notice exit fee, charged when the user unlocks its locked plenny
    uint256 public exitFee;
    /// @notice locking fee, charged when collecting the rewards
    uint256 public lockingFee;
    /// @notice number of total votes checkpoints
    uint public totalVoteNumCheckpoints;

    /// @notice arrays of locked record
    LockedRecord[] public lockedRecords;
    /// @notice indexes per address
    mapping (address => uint256[]) public recordIndexesPerAddress;
    /// @notice A record of votes checkpoints for each account, by index
    mapping (address => mapping (uint => Checkpoint)) public checkpoints;

    /// @notice The number of checkpoints for each account
    mapping (address => uint) public numCheckpoints;

    /// @notice value locked per user
    mapping(address => uint256) public userValueLocked;
    /// @notice votes per user
    mapping(address => uint256) public userVoteCount;
    /// @notice delegated votes per user
    mapping(address => uint256) public userDelegatedVotesCount;

    /// @notice total votes
    mapping (uint => Checkpoint) public totalVoteCount;

    /// @notice earned balance per user
    mapping(address => uint256) public totalUserEarned;
    /// @notice locked period per user
    mapping(address => uint256) public userLockedPeriod;
    /// @notice collected period per user
    mapping(address => uint256) public userLastCollectedPeriod;

    /// @notice has delegated to other governor
    mapping(address => bool) public hasDelegated;
    /// @notice delegation info for the given delegator address
    mapping(address => MyDelegationInfo) public myDelegatedGovernor;

    struct LockedRecord {
        address owner;
        uint256 amount;
        uint256 addedDate;
        uint256 endDate;
        uint256 multiplier;
        bool deleted;
    }

    struct Checkpoint {
        uint fromBlock;
        uint voteCount;
        uint delegatedVoteCount;
        bool isDelegating;
    }

    struct MyDelegationInfo {
        uint256 delegationIndex;
        address governor;
    }
}

