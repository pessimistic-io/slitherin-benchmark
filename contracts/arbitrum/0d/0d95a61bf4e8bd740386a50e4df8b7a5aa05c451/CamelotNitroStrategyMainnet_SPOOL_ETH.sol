//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CamelotNitroStrategy.sol";

contract CamelotNitroStrategyMainnet_SPOOL_ETH is CamelotNitroStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x835785C823e3c19c37cb6e2C616C278738947978);
    address grail = address(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    address spool = address(0xECA14F81085e5B8d1c9D32Dcb596681574723561);
    address nftPool = address(0x7e25ae5cd6bC3C6c1Df41A0CfeE123ad6C27D714);
    address nitroPool = address(0x7eceE3f0dEF3337360aF0d42798C2E1DAC5cEb87);
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
    rewardTokens = [grail, spool];
  }
}

