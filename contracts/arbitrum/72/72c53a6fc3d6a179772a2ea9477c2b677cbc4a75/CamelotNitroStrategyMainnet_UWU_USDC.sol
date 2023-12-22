//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CamelotNitroStrategy.sol";

contract CamelotNitroStrategyMainnet_UWU_USDC is CamelotNitroStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x6B8b78554Db2f017CCA749dad38E445cd8A3b5B4);
    address grail = address(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    address usdc = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address uwu = address(0x05d35769a222AfFd6185e20F3f3676Abde56C25F);
    address nftPool = address(0x4B51d227db5d0508320479532618383dA81A9539);
    address nitroPool = address(0x0fB1ADe48A1f567Ba31D3d3CAda701E0705D5077);
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
    rewardTokens = [grail, usdc, uwu];
  }
}

