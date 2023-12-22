// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./IPlennyLiqMining.sol";

/// @title  PlennyLiqMiningStorage
/// @notice Storage contract for the PlennyLiqMining
contract PlennyLiqMiningStorage is IPlennyLiqMining {

    /// @notice weight multiplier, for scaling up
    uint256 public constant WEIGHT_MULTIPLIER = 100;

    /// @notice mining reward
    uint256 public totalMiningReward;
    /// @notice total plenny amount locked
    uint256 public totalValueLocked;
    /// @notice total weight locked
    uint256 public override totalWeightLocked;
    /// @notice total weight already collected
    uint256 public totalWeightCollected;
    /// @notice distribution period, in blocks
    uint256 public nextDistributionSeconds; // 1 day
    /// @notice blocks per week
    uint256 public averageBlockCountPerWeek; // 1 week
    /// @notice maximum locking period, in blocks
    uint256 public maxPeriodWeek; // 10 years

    /// @notice  Withdrawal fee in % * 100
    uint256 public liquidityMiningFee;
    /// @notice exit fee, charged when the user withdraws its locked LPs
    uint256 public fishingFee;

    /// @notice mining reward percentage
    uint256 public liqMiningReward;

    /// @notice arrays of locked records
    LockedBalance[] public lockedBalance;
    /// @notice maps records to address
    mapping (address => uint256[]) public lockedIndexesPerAddress;
    /// @notice locked balance per address
    mapping(address => uint256) public totalUserLocked;
    /// @notice weight per address
    mapping(address => uint256) public totalUserWeight;
    /// @notice earner tokens per address
    mapping(address => uint256) public totalUserEarned;
    /// @notice locked period per address
    mapping(address => uint256) public userLockedPeriod;
    /// @notice collection period per address
    mapping(address => uint256) public userLastCollectedPeriod;

    struct LockedBalance {
        address owner;
        uint256 amount;
        uint256 addedDate;
        uint256 endDate;
        uint256 weight;
        bool deleted;
    }
}

