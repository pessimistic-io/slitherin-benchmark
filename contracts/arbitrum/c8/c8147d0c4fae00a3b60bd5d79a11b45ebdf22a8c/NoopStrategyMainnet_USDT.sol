//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./NoopStrategyUpgradeable.sol";

contract NoopStrategyMainnet_USDT is NoopStrategyUpgradeable {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    NoopStrategyUpgradeable.initializeBaseStrategy(
      _storage,
      underlying,
      _vault
    );
  }
}

