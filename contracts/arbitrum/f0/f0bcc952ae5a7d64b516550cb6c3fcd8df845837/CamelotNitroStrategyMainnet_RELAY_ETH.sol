//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CamelotNitroStrategy.sol";

contract CamelotNitroStrategyMainnet_RELAY_ETH is CamelotNitroStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xBbcF0B7F070B170909C9ff430878e92ceAd990F3);
    address grail = address(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    address relay = address(0x1426CF37CAA89628C4DA2864e40cF75E6d66Ac6b);
    address nftPool = address(0x30cbcBbd793501690d9Ca6f78fC798Ce987Af7d9);
    address nitroPool = address(0xe9b80ffd7Bd59189487Ab15866F88eBc8E7937A1);
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
    rewardTokens = [grail, relay];
  }
}

