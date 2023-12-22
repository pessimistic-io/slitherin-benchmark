//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CamelotV3NitroStrategy.sol";

contract CamelotV3NitroStrategyMainnet_ETH_USDC is CamelotV3NitroStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xd7Ef5Ac7fd4AAA7994F3bc1D273eAb1d1013530E);
    address grail = address(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    address nftPool = address(0x3b6486154b9dAe942C393b1cB3d11E3395B02Df8);
    address nitroPool = address(0x84EDB15BcBf6818879C6FDf26A69700D43100A74);
    CamelotV3NitroStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      grail,
      nftPool,
      nitroPool,
      address(0xFA10759780304c2B8d34B051C039899dFBbcad7f), //xGrail vault
      address(0x5f0AB004Ab2a3c35461e0E5Ce89839DA22B2E598), //PotPool
      address(0x1F1Ca4e8236CD13032653391dB7e9544a6ad123E) //UniProxy
    );
    rewardTokens = [grail, arb];
  }
}

