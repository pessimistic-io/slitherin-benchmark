//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CamelotNitroStrategy.sol";

contract CamelotNitroStrategyMainnet_VELA_ETH is CamelotNitroStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x4c0A68dd92449Fc06c1A651E9eb1dFfB61D64e18);
    address grail = address(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    address vela = address(0x088cd8f5eF3652623c22D48b1605DCfE860Cd704);
    address nftPool = address(0xF319A470e6d3b720824f520A8d72E8aD06B4317B);
    address nitroPool = address(0xCAd702CC3a173cbb5Dd900024e33FB7E0ab58c8E);
    CamelotNitroStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      grail,
      nftPool,
      nitroPool,
      address(0),
      address(0)
    );
    rewardTokens = [grail, vela];
  }
}

