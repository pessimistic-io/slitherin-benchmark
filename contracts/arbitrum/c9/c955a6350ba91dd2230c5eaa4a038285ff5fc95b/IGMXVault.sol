// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IGMXVault {
  function usdgAmounts(address _token) external view returns (uint256);
  function allWhitelistedTokens(uint256 _index) external view returns (address);
  function allWhitelistedTokensLength() external view returns (uint256);
  function whitelistedTokens(address _token) external view returns (bool);
  function getMinPrice(address _token) external view returns (uint256);
  function getMaxPrice(address _token) external view returns (uint256);

  function BASIS_POINTS_DIVISOR() external view returns (uint256);
  function PRICE_PRECISION() external view returns (uint256);
  function mintBurnFeeBasisPoints() external view returns (uint256);
  function taxBasisPoints() external view returns (uint256);
  function getFeeBasisPoints(address _token, uint256 _usdgAmt, uint256 _feeBasisPoints, uint256 _taxBasisPoints, bool _increment) external view returns (uint256);
  function tokenDecimals(address _token) external view returns (uint256);
}

