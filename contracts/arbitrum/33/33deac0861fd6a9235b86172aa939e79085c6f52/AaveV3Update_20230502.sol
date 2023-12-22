// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DataTypes} from "./AaveV3.sol";
import {IPool,IPoolConfigurator} from "./AaveV3.sol";
import {IEngine,EngineFlags,Rates} from "./AaveV3PayloadBase.sol";
import {   AaveV3PayloadArbitrum,   AaveV3ArbitrumAssets } from "./AaveV3PayloadArbitrum.sol";
import {   AaveV3PayloadPolygon,   AaveV3PolygonAssets } from "./AaveV3PayloadPolygon.sol";
import {   AaveV3PayloadAvalanche,   AaveV3AvalancheAssets } from "./AaveV3PayloadAvalanche.sol";
import {   AaveV3PayloadOptimism,   AaveV3OptimismAssets } from "./AaveV3PayloadOptimism.sol";


/// @dev magic value to be used as flag to keep unchanged any current configuration
/// Strongly assumes that the value AaveV3ConfigEngine.EngineFlags.KEEP_CURRENT_STRING will never be used, which seems reasonable
string constant KEEP_CURRENT_STRING = 'AaveV3ConfigEngine.EngineFlags.KEEP_CURRENT_STRING';

/// @dev magic value to be used as flag to keep unchanged any current configuration
/// Strongly assumes that the value 0x00000000000000000000000000000000000042 will never be used, which seems reasonable
address constant KEEP_CURRENT_ADDRESS = address(0x00000000000000000000000000000000000042);

struct EModeUpdate {
  uint8 eModeCategory;
  uint256 ltv;
  uint256 liqThreshold;
  uint256 liqBonus;
  address priceSource;
  string label;
}

contract AaveV3ArbitrumUpdate20230502Payload is AaveV3PayloadArbitrum {
  function collateralsUpdates() public pure override returns (IEngine.CollateralUpdate[] memory) {
    IEngine.CollateralUpdate[] memory collateralUpdates = new IEngine.CollateralUpdate[](2);

    collateralUpdates[0] = IEngine.CollateralUpdate({
      asset: AaveV3ArbitrumAssets.USDT_UNDERLYING,
      ltv: EngineFlags.KEEP_CURRENT,
      liqThreshold: EngineFlags.KEEP_CURRENT,
      liqBonus: EngineFlags.KEEP_CURRENT,
      debtCeiling: EngineFlags.KEEP_CURRENT,
      liqProtocolFee: EngineFlags.KEEP_CURRENT,
      eModeCategory: 0
    });

    collateralUpdates[1] = IEngine.CollateralUpdate({
      asset: AaveV3ArbitrumAssets.EURS_UNDERLYING,
      ltv: EngineFlags.KEEP_CURRENT,
      liqThreshold: EngineFlags.KEEP_CURRENT,
      liqBonus: EngineFlags.KEEP_CURRENT,
      debtCeiling: EngineFlags.KEEP_CURRENT,
      liqProtocolFee: EngineFlags.KEEP_CURRENT,
      eModeCategory: 0
    });

    return collateralUpdates;
  }

  function _postExecute() internal override {
    EModeUpdate[] memory eModeUpdates = new EModeUpdate[](1);

    eModeUpdates[0] = EModeUpdate({
      eModeCategory: 1,
      ltv: 9300,
      liqThreshold: 9500,
      liqBonus: EngineFlags.KEEP_CURRENT,
      priceSource: KEEP_CURRENT_ADDRESS,
      label: KEEP_CURRENT_STRING
    });

    for (uint256 i = 0; i < eModeUpdates.length; i++) {
      DataTypes.EModeCategory memory configuration = LISTING_ENGINE.POOL().getEModeCategoryData(eModeUpdates[i].eModeCategory);

      if (eModeUpdates[i].ltv == EngineFlags.KEEP_CURRENT) {
        eModeUpdates[i].ltv = configuration.ltv;
      }

      if (eModeUpdates[i].liqThreshold == EngineFlags.KEEP_CURRENT) {
        eModeUpdates[i].liqThreshold = configuration.liquidationThreshold;
      }

      if (eModeUpdates[i].liqBonus == EngineFlags.KEEP_CURRENT) {
        eModeUpdates[i].liqBonus = configuration.liquidationBonus;
      }

      if (eModeUpdates[i].priceSource == KEEP_CURRENT_ADDRESS) {
        eModeUpdates[i].priceSource = configuration.priceSource;
      }

      if (keccak256(abi.encode(eModeUpdates[i].label)) == keccak256(abi.encode(KEEP_CURRENT_STRING))) {
        eModeUpdates[i].label = configuration.label;
      }

      LISTING_ENGINE.POOL_CONFIGURATOR().setEModeCategory(
        eModeUpdates[i].eModeCategory,
        uint16(eModeUpdates[i].ltv),
        uint16(eModeUpdates[i].liqThreshold),
        uint16(eModeUpdates[i].liqBonus),
        eModeUpdates[i].priceSource,
        eModeUpdates[i].label
      );
    }
  }
}

contract AaveV3PolygonUpdate20230502Payload is AaveV3PayloadPolygon {
  function collateralsUpdates() public pure override returns (IEngine.CollateralUpdate[] memory) {
    IEngine.CollateralUpdate[] memory collateralUpdates = new IEngine.CollateralUpdate[](5);

    collateralUpdates[0] = IEngine.CollateralUpdate({
      asset: AaveV3PolygonAssets.USDT_UNDERLYING,
      ltv: EngineFlags.KEEP_CURRENT,
      liqThreshold: EngineFlags.KEEP_CURRENT,
      liqBonus: EngineFlags.KEEP_CURRENT,
      debtCeiling: EngineFlags.KEEP_CURRENT,
      liqProtocolFee: EngineFlags.KEEP_CURRENT,
      eModeCategory: 0
    });

    collateralUpdates[1] = IEngine.CollateralUpdate({
      asset: AaveV3PolygonAssets.EURS_UNDERLYING,
      ltv: EngineFlags.KEEP_CURRENT,
      liqThreshold: EngineFlags.KEEP_CURRENT,
      liqBonus: EngineFlags.KEEP_CURRENT,
      debtCeiling: EngineFlags.KEEP_CURRENT,
      liqProtocolFee: EngineFlags.KEEP_CURRENT,
      eModeCategory: 0
    });

    collateralUpdates[2] = IEngine.CollateralUpdate({
      asset: AaveV3PolygonAssets.miMATIC_UNDERLYING,
      ltv: EngineFlags.KEEP_CURRENT,
      liqThreshold: EngineFlags.KEEP_CURRENT,
      liqBonus: EngineFlags.KEEP_CURRENT,
      debtCeiling: EngineFlags.KEEP_CURRENT,
      liqProtocolFee: EngineFlags.KEEP_CURRENT,
      eModeCategory: 0
    });

    collateralUpdates[3] = IEngine.CollateralUpdate({
      asset: AaveV3PolygonAssets.jEUR_UNDERLYING,
      ltv: EngineFlags.KEEP_CURRENT,
      liqThreshold: 0,
      liqBonus: EngineFlags.KEEP_CURRENT,
      debtCeiling: EngineFlags.KEEP_CURRENT,
      liqProtocolFee: EngineFlags.KEEP_CURRENT,
      eModeCategory: 0
    });

    collateralUpdates[4] = IEngine.CollateralUpdate({
      asset: AaveV3PolygonAssets.agEUR_UNDERLYING,
      ltv: EngineFlags.KEEP_CURRENT,
      liqThreshold: 0,
      liqBonus: EngineFlags.KEEP_CURRENT,
      debtCeiling: EngineFlags.KEEP_CURRENT,
      liqProtocolFee: EngineFlags.KEEP_CURRENT,
      eModeCategory: 0
    });

    return collateralUpdates;
  }

  function _postExecute() internal override {
    EModeUpdate[] memory eModeUpdates = new EModeUpdate[](1);

    eModeUpdates[0] = EModeUpdate({
      eModeCategory: 1,
      ltv: 9300,
      liqThreshold: 9500,
      liqBonus: EngineFlags.KEEP_CURRENT,
      priceSource: KEEP_CURRENT_ADDRESS,
      label: KEEP_CURRENT_STRING
    });

    for (uint256 i = 0; i < eModeUpdates.length; i++) {
      DataTypes.EModeCategory memory configuration = LISTING_ENGINE.POOL().getEModeCategoryData(eModeUpdates[i].eModeCategory);

      if (eModeUpdates[i].ltv == EngineFlags.KEEP_CURRENT) {
        eModeUpdates[i].ltv = configuration.ltv;
      }

      if (eModeUpdates[i].liqThreshold == EngineFlags.KEEP_CURRENT) {
        eModeUpdates[i].liqThreshold = configuration.liquidationThreshold;
      }

      if (eModeUpdates[i].liqBonus == EngineFlags.KEEP_CURRENT) {
        eModeUpdates[i].liqBonus = configuration.liquidationBonus;
      }

      if (eModeUpdates[i].priceSource == KEEP_CURRENT_ADDRESS) {
        eModeUpdates[i].priceSource = configuration.priceSource;
      }

      if (keccak256(abi.encode(eModeUpdates[i].label)) == keccak256(abi.encode(KEEP_CURRENT_STRING))) {
        eModeUpdates[i].label = configuration.label;
      }

      LISTING_ENGINE.POOL_CONFIGURATOR().setEModeCategory(
        eModeUpdates[i].eModeCategory,
        uint16(eModeUpdates[i].ltv),
        uint16(eModeUpdates[i].liqThreshold),
        uint16(eModeUpdates[i].liqBonus),
        eModeUpdates[i].priceSource,
        eModeUpdates[i].label
      );
    }
  }
}

contract AaveV3AvalancheUpdate20230502Payload is AaveV3PayloadAvalanche {
  function collateralsUpdates() public pure override returns (IEngine.CollateralUpdate[] memory) {
    IEngine.CollateralUpdate[] memory collateralUpdates = new IEngine.CollateralUpdate[](2);

    collateralUpdates[0] = IEngine.CollateralUpdate({
      asset: AaveV3AvalancheAssets.USDt_UNDERLYING,
      ltv: EngineFlags.KEEP_CURRENT,
      liqThreshold: EngineFlags.KEEP_CURRENT,
      liqBonus: EngineFlags.KEEP_CURRENT,
      debtCeiling: EngineFlags.KEEP_CURRENT,
      liqProtocolFee: EngineFlags.KEEP_CURRENT,
      eModeCategory: 0
    });

    collateralUpdates[1] = IEngine.CollateralUpdate({
      asset: AaveV3AvalancheAssets.MAI_UNDERLYING,
      ltv: EngineFlags.KEEP_CURRENT,
      liqThreshold: EngineFlags.KEEP_CURRENT,
      liqBonus: EngineFlags.KEEP_CURRENT,
      debtCeiling: EngineFlags.KEEP_CURRENT,
      liqProtocolFee: EngineFlags.KEEP_CURRENT,
      eModeCategory: 0
    });

    return collateralUpdates;
  }

  function _postExecute() internal override {
    EModeUpdate[] memory eModeUpdates = new EModeUpdate[](1);

    eModeUpdates[0] = EModeUpdate({
      eModeCategory: 1,
      ltv: 9300,
      liqThreshold: 9500,
      liqBonus: EngineFlags.KEEP_CURRENT,
      priceSource: KEEP_CURRENT_ADDRESS,
      label: KEEP_CURRENT_STRING
    });

    for (uint256 i = 0; i < eModeUpdates.length; i++) {
      DataTypes.EModeCategory memory configuration = LISTING_ENGINE.POOL().getEModeCategoryData(eModeUpdates[i].eModeCategory);

      if (eModeUpdates[i].ltv == EngineFlags.KEEP_CURRENT) {
        eModeUpdates[i].ltv = configuration.ltv;
      }

      if (eModeUpdates[i].liqThreshold == EngineFlags.KEEP_CURRENT) {
        eModeUpdates[i].liqThreshold = configuration.liquidationThreshold;
      }

      if (eModeUpdates[i].liqBonus == EngineFlags.KEEP_CURRENT) {
        eModeUpdates[i].liqBonus = configuration.liquidationBonus;
      }

      if (eModeUpdates[i].priceSource == KEEP_CURRENT_ADDRESS) {
        eModeUpdates[i].priceSource = configuration.priceSource;
      }

      if (keccak256(abi.encode(eModeUpdates[i].label)) == keccak256(abi.encode(KEEP_CURRENT_STRING))) {
        eModeUpdates[i].label = configuration.label;
      }

      LISTING_ENGINE.POOL_CONFIGURATOR().setEModeCategory(
        eModeUpdates[i].eModeCategory,
        uint16(eModeUpdates[i].ltv),
        uint16(eModeUpdates[i].liqThreshold),
        uint16(eModeUpdates[i].liqBonus),
        eModeUpdates[i].priceSource,
        eModeUpdates[i].label
      );
    }
  }
}

contract AaveV3OptimismUpdate20230502Payload is AaveV3PayloadOptimism {
  function collateralsUpdates() public pure override returns (IEngine.CollateralUpdate[] memory) {
    IEngine.CollateralUpdate[] memory collateralUpdates = new IEngine.CollateralUpdate[](2);

    collateralUpdates[0] = IEngine.CollateralUpdate({
      asset: AaveV3OptimismAssets.USDT_UNDERLYING,
      ltv: EngineFlags.KEEP_CURRENT,
      liqThreshold: EngineFlags.KEEP_CURRENT,
      liqBonus: EngineFlags.KEEP_CURRENT,
      debtCeiling: EngineFlags.KEEP_CURRENT,
      liqProtocolFee: EngineFlags.KEEP_CURRENT,
      eModeCategory: 0
    });

    collateralUpdates[1] = IEngine.CollateralUpdate({
      asset: AaveV3OptimismAssets.sUSD_UNDERLYING,
      ltv: EngineFlags.KEEP_CURRENT,
      liqThreshold: EngineFlags.KEEP_CURRENT,
      liqBonus: EngineFlags.KEEP_CURRENT,
      debtCeiling: EngineFlags.KEEP_CURRENT,
      liqProtocolFee: EngineFlags.KEEP_CURRENT,
      eModeCategory: 0
    });

    return collateralUpdates;
  }

  function _postExecute() internal override {
    EModeUpdate[] memory eModeUpdates = new EModeUpdate[](1);

    eModeUpdates[0] = EModeUpdate({
      eModeCategory: 1,
      ltv: 9300,
      liqThreshold: 9500,
      liqBonus: EngineFlags.KEEP_CURRENT,
      priceSource: KEEP_CURRENT_ADDRESS,
      label: KEEP_CURRENT_STRING
    });

    for (uint256 i = 0; i < eModeUpdates.length; i++) {
      DataTypes.EModeCategory memory configuration = LISTING_ENGINE.POOL().getEModeCategoryData(eModeUpdates[i].eModeCategory);

      if (eModeUpdates[i].ltv == EngineFlags.KEEP_CURRENT) {
        eModeUpdates[i].ltv = configuration.ltv;
      }

      if (eModeUpdates[i].liqThreshold == EngineFlags.KEEP_CURRENT) {
        eModeUpdates[i].liqThreshold = configuration.liquidationThreshold;
      }

      if (eModeUpdates[i].liqBonus == EngineFlags.KEEP_CURRENT) {
        eModeUpdates[i].liqBonus = configuration.liquidationBonus;
      }

      if (eModeUpdates[i].priceSource == KEEP_CURRENT_ADDRESS) {
        eModeUpdates[i].priceSource = configuration.priceSource;
      }

      if (keccak256(abi.encode(eModeUpdates[i].label)) == keccak256(abi.encode(KEEP_CURRENT_STRING))) {
        eModeUpdates[i].label = configuration.label;
      }

      LISTING_ENGINE.POOL_CONFIGURATOR().setEModeCategory(
        eModeUpdates[i].eModeCategory,
        uint16(eModeUpdates[i].ltv),
        uint16(eModeUpdates[i].liqThreshold),
        uint16(eModeUpdates[i].liqBonus),
        eModeUpdates[i].priceSource,
        eModeUpdates[i].label
      );
    }
  }
}
