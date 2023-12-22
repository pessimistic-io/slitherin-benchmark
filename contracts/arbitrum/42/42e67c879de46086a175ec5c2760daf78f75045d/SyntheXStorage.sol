// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./IPriceOracle.sol";
import "./SyntheXToken.sol";

/**
 * @title SyntheX Storage Contract
 * @notice Stores all the data for SyntheX main contract
 * @dev This contract is used to store all the data for SyntheX main contract
 * @dev SyntheX is upgradable
 */
abstract contract SyntheXStorage {

    mapping(address => address[]) public rewardTokens;

    /// @notice RewardToken initial index
    uint256 public constant rewardInitialIndex = 1e36;

    /// @notice Reward state for each pool
    struct PoolRewardState {
        // The market's last updated rewardIndex
        uint224 index;

        // The timestamp the index was last updated at
        uint32 timestamp;
    }

    /// @notice The speed at which reward token is distributed to the corresponding market (per second)
    mapping(address => mapping(address => uint)) public rewardSpeeds;

    /// @notice The reward market borrow state for each market
    mapping(address => mapping(address => PoolRewardState)) public rewardState;
    
    /// @notice The reward borrow index for each market for each borrower as of the last time they accrued COMP
    mapping(address => mapping(address => mapping(address => uint))) public rewardIndex;
    
    /// @notice The reward accrued but not yet transferred to each user
    mapping(address => mapping(address => uint)) public rewardAccrued;
    
    /// @notice Roles for access control
    bytes32 public constant L1_ADMIN_ROLE = keccak256("L1_ADMIN_ROLE");
    bytes32 public constant L2_ADMIN_ROLE = keccak256("L2_ADMIN_ROLE");

    /// @notice Addresses of contracts
    bytes32 public constant VAULT = keccak256("VAULT");

    uint256[100] private __gap;
}
