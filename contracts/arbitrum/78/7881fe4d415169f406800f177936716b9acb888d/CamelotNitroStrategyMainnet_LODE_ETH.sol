//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CamelotNitroStrategy.sol";

contract CamelotNitroStrategyMainnet_LODE_ETH is CamelotNitroStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x49bB23DfAe944059C2403BCc255c5a9c0F851a8D);
    address grail = address(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    address lode = address(0xF19547f9ED24aA66b03c3a552D181Ae334FBb8DB);
    address nftPool = address(0x48D45129b58f0d464Bdd5023E013FFFc40512c30);
    address nitroPool = address(0x9c33453927D6698A141BdE5DDbc2fBa88BaA2d51);
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
    rewardTokens = [grail, lode];
  }
}

