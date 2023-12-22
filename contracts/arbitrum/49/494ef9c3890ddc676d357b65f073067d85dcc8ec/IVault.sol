// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

interface IVault {
  function tokenToUsdMin(address _token, uint256 _tokenAmount) external view returns (uint256);
  function getMaxPrice(address _token) external view returns (uint256);
  function getMinPrice(address _token) external view returns (uint256);
}

