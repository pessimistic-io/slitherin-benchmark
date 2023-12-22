//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CamelotNFTStrategy.sol";

contract CamelotNFTStrategyMainnet_ARB_ETH is CamelotNFTStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xa6c5C7D189fA4eB5Af8ba34E63dCDD3a635D433f);
    address grail = address(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    address nftPool = address(0x9FFC53cE956Bf040c4465B73B3cfC04569EDaEf1);
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

