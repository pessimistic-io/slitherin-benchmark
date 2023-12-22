//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CamelotNitroStrategy.sol";

contract CamelotNitroStrategyMainnet_THALES_ETH is CamelotNitroStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x8971dFb268B961a9270632f28B24F2f637c94244);
    address grail = address(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    address thales = address(0xE85B662Fe97e8562f4099d8A1d5A92D4B453bF30);
    address nftPool = address(0xB5108062de111F61E0dD585f4225ae18d1BB21D9);
    address nitroPool = address(0x41b52A004EeDacf5CAfb8cf76b8360b679372070);
    CamelotNitroStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      grail,
      nftPool,
      nitroPool,
      address(0xFA10759780304c2B8d34B051C039899dFBbcad7f), //fxGRAIL
      address(0)
    );
    rewardTokens = [grail, thales];
  }
}

