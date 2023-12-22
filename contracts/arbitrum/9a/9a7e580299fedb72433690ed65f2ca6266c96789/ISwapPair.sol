// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface ISwapPair {
  function transferFrom(
    address src,
    address dst,
    uint256 amount
  ) external returns (bool);

  function permit(
    address owner,
    address spender,
    uint256 value,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external;

  function swap(
    uint256 amount0Out,
    uint256 amount1Out,
    address to,
    bytes calldata data
  ) external;

  function burn(address to) external returns (uint256 amount0, uint256 amount1);

  function mint(address to) external returns (uint256 liquidity);

  function getReserves()
    external
    view
    returns (
      uint112 _reserve0,
      uint112 _reserve1,
      uint32 _blockTimestampLast
    );

  function getAmountOut(uint256, address) external view returns (uint256);

  function claimFees() external returns (uint256, uint256);

  function tokens() external view returns (address, address);

  function claimable0(address _account) external view returns (uint256);

  function claimable1(address _account) external view returns (uint256);

  function index0() external view returns (uint256);

  function index1() external view returns (uint256);

  function balanceOf(address _account) external view returns (uint256);

  function approve(address _spender, uint256 _value) external returns (bool);

  function reserve0() external view returns (uint256);

  function reserve1() external view returns (uint256);

  function current(address tokenIn, uint256 amountIn) external view returns (uint256 amountOut);

  function currentCumulativePrices()
    external
    view
    returns (
      uint256 reserve0Cumulative,
      uint256 reserve1Cumulative,
      uint256 blockTimestamp
    );

  function sample(
    address tokenIn,
    uint256 amountIn,
    uint256 points,
    uint256 window
  ) external view returns (uint256[] memory);

  function quote(
    address tokenIn,
    uint256 amountIn,
    uint256 granularity
  ) external view returns (uint256 amountOut);

  function stable() external view returns (bool);

  function skim(address to) external;
}

