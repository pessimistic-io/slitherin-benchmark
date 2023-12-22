// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./IPlennyValidatorElection.sol";

/// @title  PlennyValidatorElectionStorage
/// @notice Storage contact for PlennyValidatorElection
abstract contract PlennyValidatorElectionStorage is IPlennyValidatorElection {

    /// @notice election period, in blocks
    uint256 public newElectionPeriod;
    /// @notice maximum number of validators elected in a validation cycle
    uint256 public maxValidators;
    /// @notice percentage of the accumulated validation reward that will go to the user that has triggered the election.
    uint256 public userRewardPercent;

    /// @notice block of the latest election
    uint256 public override latestElectionBlock;
    /// @notice elected validators per election. An election is identified by the block number when it was triggered.
    mapping(uint256 => address[]) public electedValidators;
    /// @notice election info
    mapping(uint256 => mapping(address => Election)) public elections;
    /// @notice active elections
    mapping(uint256 => Election[]) public activeElection;
    /// @notice check if oracle is elected validator
    mapping(uint256 => mapping(address => bool)) public override validators;

    /// @notice Reward to be transferred to the user triggering the election
    mapping (uint256 => uint256) public pendingUserReward;
    /// @notice Total pending reward per cycle
    mapping (uint256 => uint256) public pendingElectionReward;
    /// @notice Reward to be transferred to oracle validators
    mapping (uint256 => mapping(address => uint256)) public pendingElectionRewardPerValidator;

    struct Election {
        uint256 created;
        uint256 revenueShare;
        uint256 stakedBalance;
        uint256 delegatedBalance;
        address[] delegators;
        uint256[] delegatorsBalance;
    }

    struct ValidatorIndex {
        uint256 index;
        bool exists;
    }

    /// @notice reward that will go to the user that has triggered the election.
    uint256 public electionTriggerUserReward;
    /// @notice election info
    mapping(uint256 => mapping(address => ElectionInfo)) public electionsArr;
    /// @notice active elections
    mapping(uint256 => ElectionInfo[]) public currentElection;

    struct ElectionInfo {
        uint256 created;
        uint256 stakedBalance;
        uint256 score;
    }
}

