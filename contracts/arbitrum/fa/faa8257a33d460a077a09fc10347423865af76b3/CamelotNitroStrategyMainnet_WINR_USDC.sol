//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CamelotNitroStrategy.sol";

contract CamelotNitroStrategyMainnet_WINR_USDC is CamelotNitroStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xAa6d06CeB39132b720b54259B70F41f9C975782A);
    address grail = address(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    address winr = address(0xD77B108d4f6cefaa0Cae9506A934e825BEccA46E);
    address nftPool = address(0xEa33C17D890f33bc2570938E4C318faa2DBaba08);
    address nitroPool = address(0x335c8Fe952924794A7a0aB59971FAcC4835B4cE0);
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
    rewardTokens = [grail, winr];
  }
}

