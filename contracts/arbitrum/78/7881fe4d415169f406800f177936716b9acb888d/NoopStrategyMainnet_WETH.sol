//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./NoopStrategyUpgradeable.sol";

contract NoopStrategyMainnet_WETH is NoopStrategyUpgradeable {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    NoopStrategyUpgradeable.initializeBaseStrategy(
      _storage,
      underlying,
      _vault
    );
  }
}

