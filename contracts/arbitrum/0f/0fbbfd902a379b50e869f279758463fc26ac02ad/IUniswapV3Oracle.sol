// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.7;

import "./IUniswapV3Factory.sol";

interface IUniswapV3Oracle {
  function UNISWAP_V3_FACTORY() external view returns (IUniswapV3Factory);

  function CARDINALITY_PER_MINUTE() external view returns (uint8);

  function supportedFeeTiers() external view returns (uint24[] memory);

  function isPairSupported(address tokenA, address tokenB)
    external
    view
    returns (bool);

  function getAllPoolsForPair(address tokenA, address tokenB)
    external
    view
    returns (address[] memory);

  function quoteAllAvailablePoolsWithTimePeriod(
    uint128 baseAmount,
    address baseToken,
    address quoteToken,
    uint32 period
  ) external view returns (uint256 quoteAmount, address[] memory queriedPools);

  function quoteSpecificFeeTiersWithTimePeriod(
    uint128 baseAmount,
    address baseToken,
    address quoteToken,
    uint24[] calldata feeTiers,
    uint32 period
  ) external view returns (uint256 quoteAmount, address[] memory queriedPools);

  function quoteSpecificPoolsWithTimePeriod(
    uint128 baseAmount,
    address baseToken,
    address quoteToken,
    address[] calldata pools,
    uint32 period
  ) external view returns (uint256 quoteAmount);

  function prepareAllAvailablePoolsWithTimePeriod(
    address tokenA,
    address tokenB,
    uint32 period
  ) external returns (address[] memory preparedPools);

  function prepareSpecificFeeTiersWithTimePeriod(
    address tokenA,
    address tokenB,
    uint24[] calldata feeTiers,
    uint32 period
  ) external returns (address[] memory preparedPools);

  function prepareSpecificPoolsWithTimePeriod(
    address[] calldata pools,
    uint32 period
  ) external;

  function prepareAllAvailablePoolsWithCardinality(
    address tokenA,
    address tokenB,
    uint16 cardinality
  ) external returns (address[] memory preparedPools);

  function prepareSpecificFeeTiersWithCardinality(
    address tokenA,
    address tokenB,
    uint24[] calldata feeTiers,
    uint16 cardinality
  ) external returns (address[] memory preparedPools);

  function prepareSpecificPoolsWithCardinality(
    address[] calldata pools,
    uint16 cardinality
  ) external;

  function addNewFeeTier(uint24 feeTier) external;
}

