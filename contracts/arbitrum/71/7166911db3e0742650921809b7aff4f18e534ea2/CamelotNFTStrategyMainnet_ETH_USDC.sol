//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CamelotNFTStrategy.sol";

contract CamelotNFTStrategyMainnet_ETH_USDC is CamelotNFTStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x84652bb2539513BAf36e225c930Fdd8eaa63CE27);
    address grail = address(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    address nftPool = address(0x6BC938abA940fB828D39Daa23A94dfc522120C11);
    CamelotNFTStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      grail,
      nftPool,
      address(0xFA10759780304c2B8d34B051C039899dFBbcad7f),
      address(0)
    );
    rewardTokens = [grail];
  }
}

