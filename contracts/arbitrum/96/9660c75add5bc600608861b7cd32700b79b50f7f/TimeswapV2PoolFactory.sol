// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {Ownership} from "./Ownership.sol";

import {ITimeswapV2OptionFactory} from "./ITimeswapV2OptionFactory.sol";

import {OptionPairLibrary} from "./OptionPair.sol";

import {ITimeswapV2PoolFactory} from "./ITimeswapV2PoolFactory.sol";

import {TimeswapV2PoolDeployer} from "./TimeswapV2PoolDeployer.sol";

import {Error} from "./Error.sol";

import {OwnableTwoSteps} from "./OwnableTwoSteps.sol";

/// @title Factory contract for TimeswapV2Pool
/// @author Timeswap Labs
contract TimeswapV2PoolFactory is ITimeswapV2PoolFactory, TimeswapV2PoolDeployer, OwnableTwoSteps {
  using OptionPairLibrary for address;
  using Ownership for address;

  /// @dev Revert when fee initialization is chosen to be larger than uint16.
  /// @param fee The chosen fee.
  error IncorrectFeeInitialization(uint256 fee);

  /* ===== MODEL ===== */

  /// @inheritdoc ITimeswapV2PoolFactory
  address public immutable override optionFactory;
  /// @inheritdoc ITimeswapV2PoolFactory
  uint256 public immutable override transactionFee;
  /// @inheritdoc ITimeswapV2PoolFactory
  uint256 public immutable override protocolFee;

  mapping(address => address) private pairs;

  address[] public override getByIndex;

  /* ===== INIT ===== */

  constructor(
    address chosenOwner,
    address chosenOptionFactory,
    uint256 chosenTransactionFee,
    uint256 chosenProtocolFee
  ) OwnableTwoSteps(chosenOwner) {
    if (chosenTransactionFee > type(uint16).max) revert IncorrectFeeInitialization(chosenTransactionFee);
    if (chosenProtocolFee > type(uint16).max) revert IncorrectFeeInitialization(chosenProtocolFee);

    optionFactory = chosenOptionFactory;
    transactionFee = chosenTransactionFee;
    protocolFee = chosenProtocolFee;
  }

  /* ===== VIEW ===== */

  /// @inheritdoc ITimeswapV2PoolFactory
  function get(address optionPair) external view override returns (address pair) {
    pair = pairs[optionPair];
  }

  /// @inheritdoc ITimeswapV2PoolFactory
  function get(address token0, address token1) external view override returns (address pair) {
    address optionPair = ITimeswapV2OptionFactory(optionFactory).get(token0, token1);
    pair = pairs[optionPair];
  }

  function numberOfPairs() external view override returns (uint256) {
    return getByIndex.length;
  }

  /* ===== UPDATE ===== */

  /// @inheritdoc ITimeswapV2PoolFactory
  function create(address token0, address token1) external override returns (address pair) {
    address optionPair = ITimeswapV2OptionFactory(optionFactory).get(token0, token1);
    if (optionPair == address(0)) Error.zeroAddress();

    pair = pairs[optionPair];
    if (pair != address(0)) Error.zeroAddress();

    pair = deploy(address(this), optionPair, transactionFee, protocolFee);

    pairs[optionPair] = pair;
    getByIndex.push(pair);

    emit Create(msg.sender, optionPair, pair);
  }
}

