//SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.9 <=0.8.19;

interface ITradingEmissionsQontroller {

  /** ACCESS CONTROLLED FUNCTIONS **/
  
  /// @notice Use the fees generated (in USD) as basis to calculate how much
  /// token reward to disburse for trading volumes. Only `FixedRateMarket`
  /// contracts may call this function.
  /// @param borrower Address of the borrower
  /// @param lender Address of the lender
  /// @param feeUSD Fees generated (in USD, scaled to 1e18)
  function updateRewards(address borrower, address lender, uint feeUSD) external;

  
  /** USER INTERFACE **/

  /// @notice Mint the unclaimed rewards to user and reset their claimable emissions
  function claimEmissions() external;

  
  /** VIEW FUNCTIONS **/

  /// @notice Checks the amount of unclaimed trading rewards that the user can claim
  /// @param account Address of the user
  /// @return uint Amount of QODA token rewards the user may claim
  function claimableEmissions(address account) external view returns(uint);

  /// @notice Get the address of the `QAdmin` contract
  /// @return address Address of `QAdmin` contract
  function qAdmin() external view returns(address);

  /// @notice Get the address of the ERC20 token to distribute
  /// @return address Address of the ERC20 token to distribute
  function underlying() external view returns(address);

  function numPhases() external view returns(uint);

  function currentPhase() external view returns(uint);

  function totalAllocation() external view returns(uint);

  function emissionsPhase(uint phase) external view returns(uint, uint, uint);
  
}

