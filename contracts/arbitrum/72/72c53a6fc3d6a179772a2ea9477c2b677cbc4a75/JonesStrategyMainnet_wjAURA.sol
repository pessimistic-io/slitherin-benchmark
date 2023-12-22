//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./JonesStrategy.sol";

contract JonesStrategyMainnet_wjAURA is JonesStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xcB9295ac65De60373A25C18d2044D517ed5da8A9);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    address miniChef = address(0x0aEfaD19aA454bCc1B1Dd86e18A7d58D0a6FAC38);
    JonesStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      miniChef,
      arb,
      2        // Pool id
    );
    rewardTokens = [arb];
  }
}

