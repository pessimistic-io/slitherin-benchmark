// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IByte3IncOnChainServices {
  function approve() external;

  function convertUsdToWei(uint256 usdAmount) external view returns (uint256 weiAmount);

  function getUSDC() external pure returns (address);

  function getWETH() external pure returns (address);

  function needsApproval() external view returns (bool);

  function purchaseFractionToken(address recipient, uint256 usdAmount) external payable returns (uint256 remainder);
}

