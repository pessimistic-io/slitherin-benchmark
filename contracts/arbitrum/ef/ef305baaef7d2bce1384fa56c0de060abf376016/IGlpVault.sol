// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

interface IGlpVault {
  function BASIS_POINTS_DIVISOR() external view returns (uint256);

  function PRICE_PRECISION() external view returns (uint256);

  function usdg() external view returns (address);

  function taxBasisPoints() external view returns (uint256);

  function mintBurnFeeBasisPoints() external view returns (uint256);

  function getMinPrice(address _token) external view returns (uint256);

  function adjustForDecimals(
    uint256 _amount,
    address _tokenDiv,
    address _tokenMul
  ) external view returns (uint256);

  function getFeeBasisPoints(
    address _token,
    uint256 _usdgDelta,
    uint256 _feeBasisPoints,
    uint256 _taxBasisPoints,
    bool _increment
  ) external view returns (uint256);
}

