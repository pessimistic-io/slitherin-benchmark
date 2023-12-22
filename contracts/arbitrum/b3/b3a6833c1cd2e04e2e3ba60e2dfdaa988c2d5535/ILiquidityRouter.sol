// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;


interface ILiquidityRouter {
  function addLiquidityETH(
    address _tranche,
    uint256 _minLpAmount,
    address _to
  ) external payable;
  function addLiquidity(
    address _tranche,
    address _token,
    uint256 _amountIn,
    uint256 _minLpAmount,
    address _to
  ) external;
  function removeLiquidityETH(
    address _tranche,
    uint256 _lpAmount,
    uint256 _minOut,
    address _to
  ) external payable;
  function removeLiquidity(
    address _tranche,
    address _tokenOut,
    uint256 _lpAmount,
    uint256 _minOut,
    address _to
  ) external;
}

