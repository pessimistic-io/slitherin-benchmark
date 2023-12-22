// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface INonfungiblePositionManager {
  struct MintParams {
    address token0;
    address token1;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0Min;
    uint256 amount1Min;
    address recipient;
    uint256 deadline;
  }

  function mint(
    MintParams calldata params
  ) external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

  struct IncreaseLiquidityParams {
    uint256 tokenId;
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0Min;
    uint256 amount1Min;
    uint256 deadline;
  }

  function increaseLiquidity(
    IncreaseLiquidityParams calldata params
  ) external payable returns (uint128 liquidity, uint256 amount0, uint256 amount1);

  struct DecreaseLiquidityParams {
    uint256 tokenId;
    uint128 liquidity;
    uint256 amount0Min;
    uint256 amount1Min;
    uint256 deadline;
  }

  function decreaseLiquidity(
    DecreaseLiquidityParams calldata params
  ) external payable returns (uint256 amount0, uint256 amount1);

  function burn(uint256 _tokenId) external payable;

  function positions(
    uint256 _tokenId
  )
    external
    view
    returns (
      uint96 _nonce,
      address _operator,
      address _token0,
      address _token1,
      uint24 _fee,
      int24 _tickLower,
      int24 _tickUpper,
      uint128 _liquidity,
      uint256 _feeGrowthInside0LastX128,
      uint256 _feeGrowthInside1LastX128,
      uint128 _tokensOwed0,
      uint128 _tokensOwed1
    );

  function createAndInitializePoolIfNecessary(
    address _token0,
    address _token1,
    uint24 _fee,
    uint160 sqrtPriceX96
  ) external payable returns (address _pool);

  function ownerOf(uint256 _tokenId) external view returns (address);

  function approve(address _spender, uint256 _tokenId) external;

  function safeTransferFrom(address _from, address _to, uint256 _tokenId) external;

  struct CollectParams {
    uint256 tokenId;
    address recipient;
    uint128 amount0Max;
    uint128 amount1Max;
  }

  function collect(
    CollectParams calldata params
  ) external payable returns (uint256 amount0, uint256 amount1);
}

