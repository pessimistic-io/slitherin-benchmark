//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CamelotNitroIFarmStrategy.sol";

contract CamelotNitroIFarmStrategyMainnet_iFARM_ETH is CamelotNitroIFarmStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xD2A7084369cC93672b2CA868757a9f327e3677a4);
    address grail = address(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    address nftPool = address(0x5DbFE78Bf6d6FDE1db1854c9A30DFb2d565e6152);
    address nitroPool = address(0x1330Ef50fb3aF24eB0c748BEbE38d059639d4158);
    CamelotNitroIFarmStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      grail,
      nftPool,
      nitroPool,
      address(0xFA10759780304c2B8d34B051C039899dFBbcad7f),
      address(0)
    );
    rewardTokens = [grail];
  }
}

