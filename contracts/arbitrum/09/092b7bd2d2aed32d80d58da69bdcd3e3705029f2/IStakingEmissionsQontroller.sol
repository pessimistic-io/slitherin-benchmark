// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IStakingEmissionsQontroller {

  /** EVENTS **/
  
  /// @notice Emitted when we move to a new emissions regime
  event NewEmissionsPerSec(uint indexed currentPeriod, uint startTime, uint emissions, uint numSecs);

  /// @notice Emitted when user claims emissions
  event ClaimEmissions(address indexed account, uint emission);
  
  /// @notice Emitted when user deposits
  event Deposit(address indexed account, uint amount);

  /// @notice Emitted when user withdraws
  event Withdraw(address indexed account, uint amount);
  
  /** ACCESS CONTROLLED FUNCTIONS **/
  
  /// @notice Credits the account with the given amount in `StakingEmissionsQontroller`
  /// This function should only be called by the veToken contract when the user
  /// claims their accrued veTokens.
  /// @param account Address of the user
  /// @param amount Amount to credit the account
  function deposit(address account, uint amount) external;

  /// @notice Cancels account's full amount and debt from `StakingEmissionsQontroller`
  /// and claims any remaining emissions for that account. This should only
  /// be called by the veToken contract when the user unstakes the underlying
  /// @param account Address of the user.
  function withdraw(address account) external;
  
  /// @notice Function to start reward distribution, can only be invoked once.
  /// @param startSec start time in second for reward distribution, 0 for current time
  function _startStaking(uint startSec) external;

  /** USER INTERFACE **/

  /// @notice Transfer accrued emissions from `StakingEmissionsQontroller` to veToken holder
  /// This function can be called by the user anytime and as often as they wish.
  function claimEmissions() external;

  /// @notice Update emissions variables of the pool
  function updatePool() external;

  /** VIEW FUNCTIONS **/

  /// @notice Calculates the amount of emissions claimable by a user by updating
  /// the pool info in memory without writing to storage so that viewing the
  /// claimable amount does not incur gas costs.
  /// @param account Address of the user
  /// @return uint Amount claimable
  function claimableEmissions(address account) external view returns(uint);

  /// @notice Get the address of the `QAdmin` contract
  /// @return address Address of `QAdmin` contract
  function qAdmin() external view returns(address);
  
  /// @notice Get the address of the `QodaERC20` contract
  /// @return address Address of `QodaERC20` contract
  function qodaERC20() external view returns(address);

  /// @notice Get the address of the `veQoda` contract
  /// @return address Address of `veQoda` contract
  function veToken() external view returns(address);

  function numPeriods() external view returns(uint);
  
  function accTokenPerShare() external view returns(uint);

  function currentPeriod() external view returns(uint);

  function endTime() external view returns(uint);

  function lastEmissionsTime() external view returns(uint);

  function emissions() external view returns(uint);

  function numSecs() external view returns(uint);

  // @return emissions per second, scaled by 1e18
  function emissionsPerSec() external view returns(uint);

  function userInfo(address account) external view returns(uint, uint, uint);
  
  function stakingPeriod(uint i) external view returns(uint, uint);
  
}

