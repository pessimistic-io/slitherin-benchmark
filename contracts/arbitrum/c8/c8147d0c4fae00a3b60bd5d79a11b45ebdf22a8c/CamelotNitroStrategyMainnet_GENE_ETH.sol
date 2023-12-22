//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CamelotNitroStrategy.sol";

contract CamelotNitroStrategyMainnet_GENE_ETH is CamelotNitroStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xa0c79678bCFbEA0a358D5FeA563100893C37a848);
    address grail = address(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    address gnome = address(0x7698Ac5D15bb3Ba7185adCBff32A80ebD9d0709B);
    address nftPool = address(0xc7044561328BE256a37b2Aaf44b42D0E4c86eFED);
    address nitroPool = address(0x1ceEA34c280346DC539281EAb8b61EBe6CF7e496);
    CamelotNitroStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      grail,
      nftPool,
      nitroPool,
      address(0xFA10759780304c2B8d34B051C039899dFBbcad7f),
      address(0)
    );
    rewardTokens = [grail, gnome];
  }
}

