// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {ITimeswapV2OptionFactory} from "./ITimeswapV2OptionFactory.sol";

import {OptionFactoryLibrary} from "./OptionFactory.sol";

import {ITimeswapV2PoolFactory} from "./ITimeswapV2PoolFactory.sol";

import {PoolFactoryLibrary} from "./PoolFactory.sol";

import {ITimeswapV2Periphery} from "./ITimeswapV2Periphery.sol";

import {Multicall} from "./Multicall.sol";

/// @title Contract which specifies functions that are required getters/deployers for pool/option addresses
contract TimeswapV2Periphery is ITimeswapV2Periphery, Multicall {
  using OptionFactoryLibrary for address;
  using PoolFactoryLibrary for address;
  /* ===== MODEL ===== */
  /// @inheritdoc ITimeswapV2Periphery
  address public immutable override optionFactory;
  /// @inheritdoc ITimeswapV2Periphery
  address public immutable override poolFactory;

  /* ===== INIT ===== */

  constructor(address chosenOptionFactory, address chosenPoolFactory) {
    optionFactory = chosenOptionFactory;
    poolFactory = chosenPoolFactory;
  }

  ///@notice function to get option contract address given token0, token1
  ///@param token0 address of token0
  ///@param token1 address of token1
  ///@return optionPair address of optionPair
  function getOption(address token0, address token1) external view returns (address optionPair) {
    optionPair = OptionFactoryLibrary.get(optionFactory, token0, token1);
  }

  ///@notice function to get pool contract address given token0, token1
  ///@param token0 address of token0
  ///@param token1 address of token1
  ///@return optionPair address of optionPair
  ///@return poolPair address of poolPair
  function getPool(address token0, address token1) external view returns (address optionPair, address poolPair) {
    (optionPair, poolPair) = PoolFactoryLibrary.get(optionFactory, poolFactory, token0, token1);
  }

  ///@notice function to deploy option contract address given token0, token1
  ///@param token0 address of token0
  ///@param token1 address of token1
  ///@return optionPair address of optionPair
  function deployOption(address token0, address token1) external returns (address optionPair) {
    optionPair = ITimeswapV2OptionFactory(optionFactory).create(token0, token1);
  }

  ///@notice function to deploy pool contract address given token0, token1
  ///@param token0 address of token0
  ///@param token1 address of token1
  ///@return poolPair address of poolPair
  function deployPool(address token0, address token1) external returns (address poolPair) {
    poolPair = ITimeswapV2PoolFactory(poolFactory).create(token0, token1);
  }
}

