// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;


interface IGoodEntryVault  {
  function tokens() external returns (address, address);
  function withdraw(uint liquidity, address token) external returns (uint amount);
  function deposit(address token, uint amount) external payable returns (uint liquidity);
  function borrow(address asset, uint amount) external;
  function repay(address token, uint amount, uint fees) external;
  function getReserves() external view returns (uint baseAmount, uint quoteAmount, uint valueX8);
  function getAdjustedReserves() external view returns (uint baseAmount, uint quoteAmount);
  function getAdjustedBaseFee(bool increaseToken0) external view returns (uint adjustedBaseFeeX4);
  function getBasePrice() external view returns (uint priceX8);
  function initProxy(address _baseToken, address _quoteToken, address _positionManager, address weth, address _oracle) external;
  function ammType() external pure returns (bytes32 _ammType);
  function setWithdrawalIntent(uint intentAmount) external;
  function updateUserBalance() external;
}
