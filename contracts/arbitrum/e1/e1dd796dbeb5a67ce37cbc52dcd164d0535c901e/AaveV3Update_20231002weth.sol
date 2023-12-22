// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IEngine,EngineFlags,Rates} from "./AaveV3PayloadBase.sol";
import {   AaveV3PayloadOptimism,   AaveV3OptimismAssets } from "./AaveV3PayloadOptimism.sol";
import {   AaveV3PayloadArbitrum,   AaveV3ArbitrumAssets } from "./AaveV3PayloadArbitrum.sol";

contract AaveV3OptimismUpdate20231002wethPayload is AaveV3PayloadOptimism {
  function rateStrategiesUpdates() public pure override returns (IEngine.RateStrategyUpdate[] memory) {
    IEngine.RateStrategyUpdate[] memory rateStrategyUpdates = new IEngine.RateStrategyUpdate[](1);

    Rates.RateStrategyParams memory paramsWETH_UNDERLYING = Rates.RateStrategyParams({
      optimalUsageRatio: EngineFlags.KEEP_CURRENT,
      baseVariableBorrowRate: _bpsToRay(0),
      variableRateSlope1: EngineFlags.KEEP_CURRENT,
      variableRateSlope2: EngineFlags.KEEP_CURRENT,
      stableRateSlope1: EngineFlags.KEEP_CURRENT,
      stableRateSlope2: EngineFlags.KEEP_CURRENT,
      baseStableRateOffset: EngineFlags.KEEP_CURRENT,
      stableRateExcessOffset: EngineFlags.KEEP_CURRENT,
      optimalStableToTotalDebtRatio: EngineFlags.KEEP_CURRENT
    });

    rateStrategyUpdates[0] = IEngine.RateStrategyUpdate({
      asset: AaveV3OptimismAssets.WETH_UNDERLYING,
      params: paramsWETH_UNDERLYING
    });

    return rateStrategyUpdates;
  }
}

contract AaveV3ArbitrumUpdate20231002wethPayload is AaveV3PayloadArbitrum {
  function rateStrategiesUpdates() public pure override returns (IEngine.RateStrategyUpdate[] memory) {
    IEngine.RateStrategyUpdate[] memory rateStrategyUpdates = new IEngine.RateStrategyUpdate[](1);

    Rates.RateStrategyParams memory paramsWETH_UNDERLYING = Rates.RateStrategyParams({
      optimalUsageRatio: EngineFlags.KEEP_CURRENT,
      baseVariableBorrowRate: _bpsToRay(0),
      variableRateSlope1: EngineFlags.KEEP_CURRENT,
      variableRateSlope2: EngineFlags.KEEP_CURRENT,
      stableRateSlope1: EngineFlags.KEEP_CURRENT,
      stableRateSlope2: EngineFlags.KEEP_CURRENT,
      baseStableRateOffset: EngineFlags.KEEP_CURRENT,
      stableRateExcessOffset: EngineFlags.KEEP_CURRENT,
      optimalStableToTotalDebtRatio: EngineFlags.KEEP_CURRENT
    });

    rateStrategyUpdates[0] = IEngine.RateStrategyUpdate({
      asset: AaveV3ArbitrumAssets.WETH_UNDERLYING,
      params: paramsWETH_UNDERLYING
    });

    return rateStrategyUpdates;
  }
}
