// SPDX-License-Identifier: NONE
pragma solidity >=0.8.9 <=0.8.19;

import "./IERC20.sol";
import "./IFeeEmissionsQontroller.sol";
import "./CustomErrors.sol";

contract DevFeeQontroller is IFeeEmissionsQontroller {

  address public _OWNER;

  event ReceiveFees(address underlyingToken, uint feeLocal);

  event TransferOwnership(address oldOwner, address newOwner);
  
  constructor(address owner) {
    _OWNER = owner;
  }

  /** ADMIN FUNCTIONS **/

  // For receiving native token
  receive() external payable {}
  
  function transferOwnership(address newOwner) public {
    if (msg.sender != _OWNER) {
      revert CustomErrors.FEQ_Unauthorized();
    }
    emit TransferOwnership(_OWNER, newOwner);
    _OWNER = newOwner;
  }

  function withdraw() public {
    if (msg.sender != _OWNER) {
      revert CustomErrors.FEQ_Unauthorized();
    }
    payable(msg.sender).transfer(address(this).balance);
  }
  
  function withdraw(address tokenAddr) public {
    if (msg.sender != _OWNER) {
      revert CustomErrors.FEQ_Unauthorized();
    }
    uint balance = IERC20(tokenAddr).balanceOf(address(this));
    IERC20(tokenAddr).transfer(msg.sender, balance);
  }

  function approve(address tokenAddr, address spender) public {
    if (msg.sender != _OWNER) {
      revert CustomErrors.FEQ_Unauthorized();
    }
    IERC20 token = IERC20(tokenAddr);
    token.approve(spender, type(uint).max);
  }

  /** ACCESS CONTROLLED FUNCTIONS  **/

  function receiveFees(IERC20 underlyingToken, uint feeLocal) external {
    emit ReceiveFees(address(underlyingToken), feeLocal);
  }

  function veIncrease(address account, uint veIncreased) external {

  }

  function veReset(address account) external {

  }

  /** USER INTERFACE **/
  
  function claimEmissions() external {

  }

  function claimEmissions(address account) external {

  }

  /** VIEW FUNCTIONS **/
  
  function claimableEmissions() external pure returns (uint) {
    return 0;
  }

  function claimableEmissions(address account) external pure returns(uint) {
    account;
    return 0;
  }
  
  function expectedClaimableEmissions() external pure returns (uint) {
    return 0;
  }
  
  function expectedClaimableEmissions(address account) external pure returns (uint) {
    account;
    return 0;
  }

  function qAdmin() external pure returns(address) {
    return address(0);
  }

  function veToken() external pure returns (address) {
    return address(0);
  }
  
  function swapContract() external pure returns (address) {
    return address(0);
  }

  function WETH() external pure returns (IERC20) {
    return IERC20(address(0));
  }

  function emissionsRound() external pure returns (uint, uint, uint) {
    return (0,0,0);
  }
  
  function emissionsRound(uint round_) external pure returns (uint, uint, uint) {
    round_;
    return (0,0,0);
  }

  function timeTillRoundEnd() external pure returns (uint) {
    return 0;
  }

  function stakedVeAtRound(address account, uint round) external pure returns (uint) {
    account;
    round;
    return 0;
  }

  function roundInterval() external pure returns (uint) {
    return 0;
  }

  function currentRound() external pure returns (uint) {
    return 0;
  }

  function lastClaimedRound() external pure returns (uint) {
    return 0;
  }

  function lastClaimedRound(address account) external pure returns (uint) {
    account;
    return 0;
  }

  function lastClaimedVeBalance() external pure returns (uint) {
    return 0;
  }

  function lastClaimedVeBalance(address account) external pure returns (uint) {
    account;
    return 0;
  }
  
  function claimedEmissions() external pure returns (uint) {
    return 0;
  }
  
  function claimedEmissions(address account) external pure returns (uint) {
    account;
    return 0;
  }

  function totalFeesAccrued() external pure returns (uint) {
    return 0;
  }

  function totalFeesClaimed() external pure returns (uint) {
    return 0;
  }

  
}

