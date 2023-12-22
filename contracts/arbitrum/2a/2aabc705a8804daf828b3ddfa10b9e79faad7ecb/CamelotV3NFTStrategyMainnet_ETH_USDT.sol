//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CamelotV3NFTStrategy.sol";

contract CamelotV3NFTStrategyMainnet_ETH_USDT is CamelotV3NFTStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x9330e26b5Fc0b7c417C6bD901528d5c65BE5cdf2);
    address grail = address(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    address nftPool = address(0xF42884071fFe17Bdd7d1710C31191023419e0CA7);
    CamelotV3NFTStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      grail,
      nftPool,
      address(0xFA10759780304c2B8d34B051C039899dFBbcad7f),
      address(0),
      address(0x1F1Ca4e8236CD13032653391dB7e9544a6ad123E) //UniProxy
    );
    rewardTokens = [grail];
  }
}

