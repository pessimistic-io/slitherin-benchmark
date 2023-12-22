//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CompoundStrategy.sol";

contract CompoundStrategyMainnet_USDC is CompoundStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address market = address(0xA5EDBDD9646f8dFF606d7448e414884C7d905dCA);
    address rewards = address(0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae);
    address comp = address(0x354A6dA3fcde098F8389cad84b0182725c6C91dE);
    CompoundStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      market,
      rewards,
      comp
    );
  }
}

