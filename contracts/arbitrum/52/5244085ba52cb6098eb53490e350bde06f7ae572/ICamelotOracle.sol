// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICamelotOracle {
  function lpToken(
    address _token0,
    address _token1
  ) external view returns (address);

  function getAmountsOut(
    uint256 _amountIn,
    address[] memory path
  ) external view returns (uint256[] memory amounts);

  function getAmountsIn(
    uint256 _amountOut,
    uint256 _reserveIn,
    uint256 _reserveOut,
    uint256 _fee
  ) external view returns (uint256);

  function getLpTokenReserves(
    uint256 _amount,
    address _tokenA,
    address _tokenB,
    address _pair
  ) external view returns (uint256, uint256);

  function getLpTokenFees(
    address _tokenA,
    address _tokenB,
    address _pair
  ) external view returns (uint16, uint16);

  function getLpTokenValue(
    uint256 _amount,
    address _tokenA,
    address _tokenB,
    address _pair
  ) external view returns (uint256);

  function getLpTokenAmount(
    uint256 _value,
    address _tokenA,
    address _tokenB,
    address _pair
  ) external view returns (uint256);
}

