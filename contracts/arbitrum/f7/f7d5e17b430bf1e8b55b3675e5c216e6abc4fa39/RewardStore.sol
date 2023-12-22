// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./Roles.sol";

/// @title RewardStore
/// @notice Storage of reward data per user and token
contract RewardStore is Roles {

    // user => token => amount
    mapping(address => mapping(address => uint256)) private rewards;

    constructor(RoleStore rs) Roles(rs) {}

    function incrementReward(address user, address token, uint256 amount) external onlyContract {
        rewards[user][token] += amount;
    }

    function decrementReward(address user, address token, uint256 amount) external onlyContract {
        rewards[user][token] = rewards[user][token] <= amount ? 0 : rewards[user][token] - amount;
    }

    function getReward(address user, address token) external view returns (uint256) {
        return rewards[user][token];
    }

}

