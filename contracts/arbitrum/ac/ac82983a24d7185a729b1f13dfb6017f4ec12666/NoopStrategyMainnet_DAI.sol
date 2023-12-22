//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./NoopStrategyUpgradeable.sol";

contract NoopStrategyMainnet_DAI is NoopStrategyUpgradeable {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);
    NoopStrategyUpgradeable.initializeBaseStrategy(
      _storage,
      underlying,
      _vault
    );
  }
}

