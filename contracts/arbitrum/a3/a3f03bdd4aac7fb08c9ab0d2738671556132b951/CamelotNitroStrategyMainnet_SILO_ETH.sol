//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CamelotNitroStrategy.sol";

contract CamelotNitroStrategyMainnet_SILO_ETH is CamelotNitroStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xE01E0B5C707EdEE3FFC10b464115cC20073817A2);
    address grail = address(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    address silo = address(0x0341C0C0ec423328621788d4854119B97f44E391);
    address nftPool = address(0x48776552223FFca23125e8E9509E949732FAee72);
    address nitroPool = address(0x4C5d499252c932822df31C921747F89F6a7f92ED);
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
    rewardTokens = [grail, silo];
  }
}

