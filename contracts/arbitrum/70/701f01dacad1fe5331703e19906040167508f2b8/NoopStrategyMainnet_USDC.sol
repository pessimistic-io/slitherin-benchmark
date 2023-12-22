//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./NoopStrategyUpgradeable.sol";

contract NoopStrategyMainnet_USDC is NoopStrategyUpgradeable {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    NoopStrategyUpgradeable.initializeBaseStrategy(
      _storage,
      underlying,
      _vault
    );
  }
}

