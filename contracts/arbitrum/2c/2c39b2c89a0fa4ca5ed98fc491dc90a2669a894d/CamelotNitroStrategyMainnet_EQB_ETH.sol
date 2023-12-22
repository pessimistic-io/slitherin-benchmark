//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CamelotNitroStrategy.sol";

contract CamelotNitroStrategyMainnet_EQB_ETH is CamelotNitroStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x69B545997BD6aBC81CaE39Fe9bdC94d2242a0f92);
    address grail = address(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    address eqb = address(0xBfbCFe8873fE28Dfa25f1099282b088D52bbAD9C);
    address nftPool = address(0x76075F03e0Ae34bF0B63bcFb731F9DB5F826dcAe);
    address nitroPool = address(0xE13B64C33eCB0501C21e0423fcd2efAF5e0a2592);
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
    rewardTokens = [grail, eqb];
  }
}

