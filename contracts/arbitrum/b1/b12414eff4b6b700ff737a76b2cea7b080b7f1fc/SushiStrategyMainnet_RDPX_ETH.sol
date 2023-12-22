//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./SushiStrategy.sol";

contract SushiStrategyMainnet_RDPX_ETH is SushiStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x7418F5A2621E13c05d1EFBd71ec922070794b90a);
    address dpx = address(0x6C2C06790b3E3E3c38e12Ee22F8183b37a13EE55);
    address rdpx = address(0x32Eb7902D4134bf98A28b963D26de779AF92A212);
    address sushi = address(0xd4d42F0b6DEF4CE0383636770eF773390d85c61A);
    address miniChef = address(0xF4d73326C13a4Fc5FD7A064217e12780e9Bd62c3);
    SushiStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      miniChef,
      23        // Pool id
    );
    rewardTokens = [dpx, sushi];
    reward2WETH[dpx] = [dpx, weth];
    reward2WETH[sushi] = [sushi, weth];
    WETH2deposit[rdpx] = [weth, rdpx];
  }
}

