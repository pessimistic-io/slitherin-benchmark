//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./AuraStrategy.sol";

contract AuraStrategyMainnet_MAGIC_USDC is AuraStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xb3028Ca124B80CFE6E9CA57B70eF2F0CCC41eBd4);
    address aura = address(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address usdc = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address rewardPool = address(0xa4a5be1f830a6e94B844E12f86D97ff54a01A573);
    AuraStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      0xb3028ca124b80cfe6e9ca57b70ef2f0ccc41ebd40002000000000000000000ba,  // Balancer Pool id
      6,      // Aura Pool id
      usdc   //depositToken
    );
    rewardTokens = [aura, bal];
  }
}

