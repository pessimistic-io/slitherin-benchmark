// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {AutomationCompatible} from "./AutomationCompatible.sol";

import {ISmartYieldAave} from "./ISmartYieldAave.sol";

/// @title Smart Yield Aave V2 Originator Term Liquidation
contract SYAaveTermLiquidation is AutomationCompatible {

  ISmartYieldAave public smartYield;

  constructor(ISmartYieldAave _smartYield) {
    smartYield = _smartYield;
  }

  function checkUpkeep(bytes calldata) external pure override returns (
    bool upkeepNeeded,
    bytes memory
  ) {
    return (true, "");
  }

  function performUpkeep(bytes calldata) external {
    address activeTerm = smartYield.activeTerm();
    smartYield.liquidateTerm(activeTerm);
  }

}

