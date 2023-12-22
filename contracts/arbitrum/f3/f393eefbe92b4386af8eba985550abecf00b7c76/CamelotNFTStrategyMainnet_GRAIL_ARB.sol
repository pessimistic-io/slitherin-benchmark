//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CamelotNFTStrategy.sol";

contract CamelotNFTStrategyMainnet_GRAIL_ARB is CamelotNFTStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xC9da32C3b444F15412F7FeAC6104d1E258D23B1b);
    address grail = address(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    address nftPool = address(0x2a9766A73999a7dE16A4b4E345c8a6fC4E4288Cc);
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

