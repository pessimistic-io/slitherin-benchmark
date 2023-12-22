// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./IPlennyStaking.sol";

/// @title  PlennyStakingStorage
/// @notice storage contract for PlennyStaking
abstract contract PlennyStakingStorage is IPlennyStaking {

    /// @notice withdraw fee charged when user withdraw from staking
    uint256 public withdrawFee;

    /// @notice all plenny stakers
    address[] public plennyOwners;

    /// @notice staked balance per user
    mapping(address => uint256) public override plennyBalance;
    /// @dev staker exists
    mapping(address => bool) internal plennyOwnerExists;
}

