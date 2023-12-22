// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ILendingPool {
  function totalValue() external view returns (uint256);
  function totalAvailableSupply() external view returns (uint256);
  function utilizationRate() external view returns (uint256);
  function exchangeRate() external view returns (uint256);
  function borrowAPR() external view returns (uint256);
  function lendingAPR() external view returns (uint256);
  function maxRepay(address _address) external view returns (uint256);
  function deposit(uint256 _assetAmount, uint256 _minSharesAmount) external;
  function withdraw(uint256 _ibTokenAmount, uint256 _minWithdrawAmount) external;
  function borrow(uint256 _assetAmount) external;
  function repay(uint256 _repayAmount) external;
  function updateProtocolFee(uint256 _protocolFee) external;
  function withdrawReserve(uint256 _amount) external;
}

