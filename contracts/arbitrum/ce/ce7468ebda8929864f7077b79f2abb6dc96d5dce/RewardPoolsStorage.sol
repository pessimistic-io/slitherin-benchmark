// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

abstract contract RewardPoolsStorage {
    address public investmentPoolsContractAddress;

    address public rewardTokenAddress;

    uint256 public rewardCheckPeriodInSeconds;

    mapping(address => bool) public controller;

    mapping(uint256 => bool) public rewardPoolCreatedForPoolId;

    mapping(uint256 => uint256) public rewardCheckPeriodForPoolId;

    mapping(uint256 => uint256) public rewardAmountPerPoolId;

    mapping(uint256 => uint256) public claimedAmountPerPoolId;

    mapping(uint256 => mapping(address => bool)) public userClaimedPerPoolId;

    /// @dev Events
    event RewardPoolCreated(
        address account,
        uint256 poolId,
        uint256 rewardAmount,
        uint256 createdTimestamp
    );

    event ClaimedReward(
        address account,
        uint256 poolId,
        uint256 rewardAmount,
        uint256 claimedTimestamp,
        uint256 totalAmountClaimedForThisPoolId
    );

    address public protocolFeeReceiver;

    uint256 public protocolFeePercentage;
}

