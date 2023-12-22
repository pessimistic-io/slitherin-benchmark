//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CamelotNitroStrategy.sol";

contract CamelotNitroStrategyMainnet_GNOME_ETH is CamelotNitroStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x60F7116d7c451ac5a5159F60Fc5fC36336b742c4);
    address grail = address(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    address gene = address(0x59A729658e9245B0cF1f8Cb9fb37945D2B06ea27);
    address nftPool = address(0x1e527Dc9B55DD46DE058239ff33907a5b6E396D1);
    address nitroPool = address(0x7F2a4E30bC0c9eB68CC3644516bA2c4b4b481F1c);
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
    rewardTokens = [grail, gene];
  }
}

