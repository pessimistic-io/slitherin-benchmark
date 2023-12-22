// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {ITimeswapV2OptionFactory} from "./ITimeswapV2OptionFactory.sol";

import {ITimeswapV2PoolFactory} from "./ITimeswapV2PoolFactory.sol";

/// @dev Library to verify that a pool or option exist
library Verify {
  /// @dev Revert with this error when an address other than the options contract call the implemented callback function.
  error CanOnlyBeCalledByOptionContract();

  /// @dev Revert with this error when an address other than the pool contract call the implemented callback function.
  error CanOnlyBeCalledByPoolContract();

  /// @dev Revert with this error when an address other than the tokens contract call the implemented callback function.
  error CanOnlyBeCalledByTokensContract();

  /// @dev Revert with this error when an address other than the liquidity tokens contract call the implemented callback function.
  error CanOnlyBeCalledByLiquidityTokensContract();

  /// @dev Checks that the option given the parameters exist and that the msg.sender is the options contract.
  /// @param optionFactory The address of the Timeswap V2 option factory contract.
  /// @param token0 The address of the smaller sized ERC20 contract.
  /// @param token1 The address of the larger sized ERC20 contract.
  function timeswapV2Option(address optionFactory, address token0, address token1) internal view {
    address optionPair = ITimeswapV2OptionFactory(optionFactory).get(token0, token1);

    if (optionPair != msg.sender) revert CanOnlyBeCalledByOptionContract();
  }

  /// @dev Checks that the pool given the parameters exist and that the msg.sender is the pool contract.
  /// @dev Also returns the address of the optionPair.
  /// @param optionFactory The address of the Timeswap V2 option factory contract.
  /// @param poolFactory The address of the Timeswap V2 pool factory contract.
  /// @param token0 The address of the smaller sized ERC20 contract.
  /// @param token1 The address of the larger sized ERC20 contract.
  /// @return optionPair The address of the option pair contract.
  function timeswapV2Pool(
    address optionFactory,
    address poolFactory,
    address token0,
    address token1
  ) internal view returns (address optionPair) {
    optionPair = ITimeswapV2OptionFactory(optionFactory).get(token0, token1);

    address poolPair = ITimeswapV2PoolFactory(poolFactory).get(optionPair);

    if (poolPair != msg.sender) revert CanOnlyBeCalledByPoolContract();
  }

  /// @dev Checks that the msg.sender is the tokens contract.
  function timeswapV2Token(address tokens) internal view {
    if (tokens != msg.sender) revert CanOnlyBeCalledByTokensContract();
  }

  /// @dev Checks that the msg.sender is the liquidity tokens contract.
  function timeswapV2LiquidityToken(address liquidityTokens) internal view {
    if (liquidityTokens != msg.sender) revert CanOnlyBeCalledByLiquidityTokensContract();
  }
}

