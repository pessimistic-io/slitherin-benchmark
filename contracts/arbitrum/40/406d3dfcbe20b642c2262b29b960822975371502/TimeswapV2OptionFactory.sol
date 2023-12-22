// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {Error} from "./Error.sol";

import {ITimeswapV2OptionFactory} from "./ITimeswapV2OptionFactory.sol";

import {TimeswapV2OptionDeployer} from "./TimeswapV2OptionDeployer.sol";

import {OptionPairLibrary} from "./OptionPair.sol";

/// @title Deploys Timeswap V2 Option pair contracts
/// @author Timeswap Labs
contract TimeswapV2OptionFactory is ITimeswapV2OptionFactory, TimeswapV2OptionDeployer {
  using SafeERC20 for IERC20;

  /* ===== MODEL ===== */

  mapping(address => mapping(address => address)) private optionPairs;

  /// @inheritdoc ITimeswapV2OptionFactory
  address[] public override getByIndex;

  /* ===== VIEW ===== */

  /// @inheritdoc ITimeswapV2OptionFactory
  function get(address token0, address token1) external view override returns (address optionPair) {
    OptionPairLibrary.checkCorrectFormat(token0, token1);
    optionPair = optionPairs[token0][token1];
  }

  /// @inheritdoc ITimeswapV2OptionFactory
  function numberOfPairs() external view override returns (uint256) {
    return getByIndex.length;
  }

  /* ===== UPDATE ===== */

  /// @inheritdoc ITimeswapV2OptionFactory
  function create(address token0, address token1) external override returns (address optionPair) {
    if (token0 == address(0)) Error.zeroAddress();
    if (token1 == address(0)) Error.zeroAddress();
    OptionPairLibrary.checkCorrectFormat(token0, token1);

    optionPair = optionPairs[token0][token1];
    OptionPairLibrary.checkDoesNotExist(token0, token1, optionPair);

    optionPair = deploy(address(this), token0, token1);

    optionPairs[token0][token1] = optionPair;
    getByIndex.push(optionPair);

    emit Create(msg.sender, token0, token1, optionPair);
  }
}

