// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IEngine,EngineFlags,Rates} from "./AaveV3PayloadBase.sol";
import {   AaveV3PayloadArbitrum,   AaveV3ArbitrumAssets } from "./AaveV3PayloadArbitrum.sol";
import {   AaveV3PayloadOptimism,   AaveV3OptimismAssets } from "./AaveV3PayloadOptimism.sol";
import {   AaveV3PayloadPolygon,   AaveV3PolygonAssets } from "./AaveV3PayloadPolygon.sol";
import {   AaveV3PayloadAvalanche,   AaveV3AvalancheAssets } from "./AaveV3PayloadAvalanche.sol";

contract AaveV3ArbitrumUpdate20230909Payload is AaveV3PayloadArbitrum {
  function collateralsUpdates() public pure override returns (IEngine.CollateralUpdate[] memory) {
    IEngine.CollateralUpdate[] memory collateralUpdates = new IEngine.CollateralUpdate[](1);

    collateralUpdates[0] = IEngine.CollateralUpdate({
      asset: AaveV3ArbitrumAssets.MAI_UNDERLYING,
      ltv: 0,
      liqThreshold: EngineFlags.KEEP_CURRENT,
      liqBonus: EngineFlags.KEEP_CURRENT,
      debtCeiling: EngineFlags.KEEP_CURRENT,
      liqProtocolFee: EngineFlags.KEEP_CURRENT,
      eModeCategory: EngineFlags.KEEP_CURRENT
    });

    return collateralUpdates;
  }

  function _postExecute() internal override {
    LISTING_ENGINE.POOL_CONFIGURATOR().setReserveFreeze(
      AaveV3ArbitrumAssets.MAI_UNDERLYING,
      true
    );
  }
}

contract AaveV3OptimismUpdate20230909Payload is AaveV3PayloadOptimism {
  function collateralsUpdates() public pure override returns (IEngine.CollateralUpdate[] memory) {
    IEngine.CollateralUpdate[] memory collateralUpdates = new IEngine.CollateralUpdate[](1);

    collateralUpdates[0] = IEngine.CollateralUpdate({
      asset: AaveV3OptimismAssets.MAI_UNDERLYING,
      ltv: 0,
      liqThreshold: EngineFlags.KEEP_CURRENT,
      liqBonus: EngineFlags.KEEP_CURRENT,
      debtCeiling: EngineFlags.KEEP_CURRENT,
      liqProtocolFee: EngineFlags.KEEP_CURRENT,
      eModeCategory: EngineFlags.KEEP_CURRENT
    });

    return collateralUpdates;
  }

  function _postExecute() internal override {
    LISTING_ENGINE.POOL_CONFIGURATOR().setReserveFreeze(
      AaveV3OptimismAssets.MAI_UNDERLYING,
      true
    );
  }
}

contract AaveV3PolygonUpdate20230909Payload is AaveV3PayloadPolygon {
  function collateralsUpdates() public pure override returns (IEngine.CollateralUpdate[] memory) {
    IEngine.CollateralUpdate[] memory collateralUpdates = new IEngine.CollateralUpdate[](1);

    collateralUpdates[0] = IEngine.CollateralUpdate({
      asset: AaveV3PolygonAssets.miMATIC_UNDERLYING,
      ltv: 0,
      liqThreshold: EngineFlags.KEEP_CURRENT,
      liqBonus: EngineFlags.KEEP_CURRENT,
      debtCeiling: EngineFlags.KEEP_CURRENT,
      liqProtocolFee: EngineFlags.KEEP_CURRENT,
      eModeCategory: EngineFlags.KEEP_CURRENT
    });

    return collateralUpdates;
  }

  function _postExecute() internal override {
    LISTING_ENGINE.POOL_CONFIGURATOR().setReserveFreeze(
      AaveV3PolygonAssets.miMATIC_UNDERLYING,
      true
    );
  }
}

contract AaveV3AvalancheUpdate20230909Payload is AaveV3PayloadAvalanche {
  function collateralsUpdates() public pure override returns (IEngine.CollateralUpdate[] memory) {
    IEngine.CollateralUpdate[] memory collateralUpdates = new IEngine.CollateralUpdate[](1);

    collateralUpdates[0] = IEngine.CollateralUpdate({
      asset: AaveV3AvalancheAssets.MAI_UNDERLYING,
      ltv: 0,
      liqThreshold: EngineFlags.KEEP_CURRENT,
      liqBonus: EngineFlags.KEEP_CURRENT,
      debtCeiling: EngineFlags.KEEP_CURRENT,
      liqProtocolFee: EngineFlags.KEEP_CURRENT,
      eModeCategory: EngineFlags.KEEP_CURRENT
    });

    return collateralUpdates;
  }

  function _postExecute() internal override {
    LISTING_ENGINE.POOL_CONFIGURATOR().setReserveFreeze(
      AaveV3AvalancheAssets.MAI_UNDERLYING,
      true
    );
  }
}

