//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./XGrailStrategyV2.sol";

contract XGrailStrategyV2Mainnet_XGrail is XGrailStrategyV2 {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x3CAaE25Ee616f2C8E13C74dA0813402eae3F496b);
    address grail = address(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    address yieldBooster = address(0xD27c373950E7466C53e5Cd6eE3F70b240dC0B1B1);
    address ethUsdc = address(0xd7Ef5Ac7fd4AAA7994F3bc1D273eAb1d1013530E);
    XGrailStrategyV2.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      grail,
      yieldBooster
    );
    rewardTokens = [ethUsdc];
    isLp[ethUsdc] = true;
    TargetAllocation memory initialAllocation;
    initialAllocation.allocationAddress = dividendsAddress();
    initialAllocation.weight = 10000;
    initialAllocation.data = new bytes(0);
    allocationTargets.push(initialAllocation);
  }
}

