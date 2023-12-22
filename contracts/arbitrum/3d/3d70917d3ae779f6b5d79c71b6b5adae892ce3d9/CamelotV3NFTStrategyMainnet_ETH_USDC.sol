//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CamelotV3NFTStrategy.sol";

contract CamelotV3NFTStrategyMainnet_ETH_USDC is CamelotV3NFTStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xd7Ef5Ac7fd4AAA7994F3bc1D273eAb1d1013530E);
    address grail = address(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    address nftPool = address(0x3b6486154b9dAe942C393b1cB3d11E3395B02Df8);
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

