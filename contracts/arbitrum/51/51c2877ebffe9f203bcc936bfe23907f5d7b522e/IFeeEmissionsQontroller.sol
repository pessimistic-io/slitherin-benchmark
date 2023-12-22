//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IERC20.sol";

interface IFeeEmissionsQontroller {

  /// @notice Emitted when user claims emissions
  event ClaimEmissions(address indexed account, uint amount);

  /// @notice Emitted when fee is accrued in a round
  event FeesAccrued(uint indexed round, address token, uint amount, uint amountInRound);

  /// @notice Emitted when we move to a new round
  event NewFeeEmissionsRound(uint indexed currentPeriod, uint startTime, uint endTime);

  /** ACCESS CONTROLLED FUNCTIONS **/

  function receiveFees(IERC20 underlyingToken, uint feeLocal) external;

  function veIncrease(address account, uint veIncreased) external;

  function veReset(address account) external;

  /** USER INTERFACE **/

  function claimEmissions() external;

  function claimEmissions(address account) external;


  /** VIEW FUNCTIONS **/
  
  function claimableEmissions() external view returns (uint);
  
  function claimableEmissions(address account) external view returns (uint);
  
  function expectedClaimableEmissions() external view returns (uint);
  
  function expectedClaimableEmissions(address account) external view returns (uint);

  function qAdmin() external view returns (address);

  function veToken() external view returns (address);

  function swapContract() external view returns (address);

  function WETH() external view returns (IERC20);

  function emissionsRound() external view returns (uint, uint, uint);
  
  function emissionsRound(uint round_) external view returns (uint, uint, uint);

  function timeTillRoundEnd() external view returns (uint);

  function stakedVeAtRound(address account, uint round) external view returns (uint);

  function roundInterval() external view returns (uint);

  function currentRound() external view returns (uint);

  function lastClaimedRound() external view returns (uint);

  function lastClaimedRound(address account) external view returns (uint);

  function lastClaimedVeBalance() external view returns (uint);

  function lastClaimedVeBalance(address account) external view returns (uint);
  
  function claimedEmissions() external view returns (uint);
    
  function claimedEmissions(address account) external view returns (uint);

  function totalFeesAccrued() external view returns (uint);

  function totalFeesClaimed() external view returns (uint);

}

