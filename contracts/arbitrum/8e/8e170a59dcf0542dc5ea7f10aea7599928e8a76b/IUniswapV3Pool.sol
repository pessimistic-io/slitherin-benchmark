// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IUniswapV3Pool {
  function snapshotCumulativesInside(
    int24 _tickLower,
    int24 _tickUpper
  ) external view returns (int56, uint160, uint32);

  struct Slot0 {
    uint160 sqrtPriceX96;
    int24 tick;
    uint16 observationIndex;
    uint16 observationCardinality;
    uint16 observationCardinalityNext;
    uint32 feeProtocol;
    bool unlocked;
  }

  function slot0()
    external
    view
    returns (
      uint160 sqrtPriceX96,
      int24 tick,
      uint16 observationIndex,
      uint16 observationCardinality,
      uint16 observationCardinalityNext,
      uint32 feeProtocol,
      bool unlocked
    );

  function token0() external view returns (address);

  function token1() external view returns (address);

  function fee() external view returns (uint24);

  function tickSpacing() external view returns (int24);
}
