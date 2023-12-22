// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IERC20.sol";
import "./InterestRateModel.sol";

interface MTokenInterface is IERC20 {
 
  function accrualBlockTimestamp() external view returns(uint);
  function exchangeRateStored() external view returns(uint);
  function getCash() external view returns(uint);
  function totalBorrows() external view returns(uint);
  function totalReserves() external view returns(uint);
  function reserveFactorMantissa() external view returns(uint);
  function interestRateModel() external view returns(InterestRateModel);
  
}

interface MErc20Interface is MTokenInterface {

  function mint(uint mintAmount) external returns (uint);
  function redeem(uint redeemTokens) external returns (uint);
  function redeemUnderlying(uint redeemAmount) external returns (uint);
  function borrow(uint borrowAmount) external returns (uint);
  function repayBorrow(uint repayAmount) external returns (uint);
  function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint);
  function liquidateBorrow(address borrower, uint repayAmount, MTokenInterface mTokenCollateral) external returns (uint);
  
}

interface MGlimmerInterface is MTokenInterface {

  function mint() external payable;
  function redeem(uint redeemTokens) external returns (uint);
  function redeemUnderlying(uint redeemAmount) external returns (uint);
  function borrow(uint borrowAmount) external returns (uint);
  function repayBorrow() external payable;
  function repayBorrowBehalf(address borrower) external payable;
  function liquidateBorrow(address borrower, MTokenInterface mTokenCollateral) external payable;
  
}

