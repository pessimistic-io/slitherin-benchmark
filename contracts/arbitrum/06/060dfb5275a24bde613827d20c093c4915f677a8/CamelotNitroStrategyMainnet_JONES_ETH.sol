//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CamelotNitroStrategy.sol";

contract CamelotNitroStrategyMainnet_JONES_ETH is CamelotNitroStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x460c2c075340EbC19Cf4af68E5d83C194E7D21D0);
    address grail = address(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    address nftPool = address(0xE20cE7d800934eC568Fe94E135E84b1e919AbB2a);
    address nitroPool = address(0xda2257dd3501Cd96164eEf0C744E2ee30E646A40);
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
    rewardTokens = [grail];
  }
}

