//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./LodestarFoldStrategy.sol";

contract LodestarFoldStrategyMainnet_USDT is LodestarFoldStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    address cToken = address(0x9365181A7df82a1cC578eAE443EFd89f00dbb643);
    address comptroller = address(0xa86DD95c210dd186Fa7639F93E4177E97d057576);
    address lode = address(0xF19547f9ED24aA66b03c3a552D181Ae334FBb8DB);
    LodestarFoldStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      cToken,
      comptroller,
      lode,
      680,
      700,
      1000,
      true
    );
  }
}
