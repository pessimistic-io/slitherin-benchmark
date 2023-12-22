// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IERC20Upgradeable.sol";

interface IVeQoda is IERC20Upgradeable {

  /** EVENTS **/
  
  /// @notice Emitted when user stakes underlying QODA
  event Stake(address indexed account, uint amount);

  /// @notice Emitted when user unstakes underlying QODA
  event Unstake(address indexed account, uint amount);

  /// @notice Emitted when user claims veToken
  event Claim(address indexed account, uint amount);

  /** USER INTERFACE **/
  
  /// @notice Stake underlying into contract
  /// @param amount Amount of underlying to stake
  function stake(uint256 amount) external;
  
  /// @notice Unstake underlying tokens
  /// NOTE: You will lose ALL your veToken if you unstake ANY amount of underlying tokens
  /// @param amount Amount of underlying tokens to unstake
  function unstake(uint amount) external;

  /// @notice Claims accumulated veToken
  function claimVeToken() external;

  /// @notice Claims accumulated veToken on behalf of an account
  function claimVeToken(address account) external;
  
  /** VIEW FUNCTIONS **/

  /// @notice Get the address of the `QAdmin`
  /// @return address
  function qAdmin() external view returns(address);
  
  /// @notice checks whether user has underlying staked
  /// @param account The user address to check
  /// @return true if the user has underlying in stake, false otherwise
  function hasStaked(address account) external view returns (bool);
  
  /// @notice Calculate the amount of veToken that can be claimed by user
  /// @param account Address to check
  /// @return uint Amount of veToken that can be claimed by user
  function claimableVeToken(address account) external view returns(uint);
  
  /// @notice Returns the underlying amount of underlying staked by the user
  /// @param account User address to check
  /// @return uint Amount of staked underlying underlying
  function getStakedAmount(address account) external view returns(uint);

  function qodaERC20() external view returns(address);

  function stakingEmissionsQontroller() external view returns(address);

  function feeEmissionsQontroller() external view returns(address);

  function veTokenPerSec() external view returns(uint);

  function maxVeToken() external view returns(uint);
}

