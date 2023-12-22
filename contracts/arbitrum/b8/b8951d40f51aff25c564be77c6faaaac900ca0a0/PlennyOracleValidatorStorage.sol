// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./IPlennyOracleValidator.sol";

/// @title  PlennyOracleValidatorStorage
/// @notice Storage contract for the PlennyOracleValidator
contract PlennyOracleValidatorStorage is IPlennyOracleValidator {

    /// @notice quorum
    uint public minQuorumDivisor;
    /// @notice total reward for the oracle validations
    uint256 public totalOracleReward;
    /// @notice fixed amount reward given to the oracle validation when validating
    uint256 public oracleFixedRewardAmount;
    /// @notice percentage amount reward (from PlennyTreasury) given to the oracle validation when validating
    uint256 public oracleRewardPercentage;
    /// @dev percentage of the reward that goes for the validator (i.e leader) that has posted the data on-chain.
    uint256 internal leaderRewardPercent;

    /// @notice all oracle validations
    mapping(uint256 => mapping(address => uint256)) public override oracleValidations;

    /// @notice validations for opened channel
    mapping(uint256 => mapping(address => bool)) public oracleOpenChannelAnswers;
    /// @dev the oracle validators that have reached consensus on a opened channel
    mapping(uint256 => address []) internal oracleOpenChannelConsensus;
    /// @dev the data for the opened channel as agreed by the oracle validators
    mapping(uint256 => bytes32) internal latestOpenChannelAnswer;

    /// @notice validations for closed channel
    mapping(uint256 => mapping(address => bool)) public oracleCloseChannelAnswers;
    /// @dev the oracle validators that have reached consensus on a closed channel
    mapping(uint256 => address []) internal oracleCloseChannelConsensus;
    /// @dev the data for the closed channel as agreed by the oracle validators
    mapping(uint256 => bytes32) internal latestCloseChannelAnswer;
}

