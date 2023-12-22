// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IEngine,EngineFlags,Rates} from "./AaveV3PayloadBase.sol";
import {   AaveV3PayloadArbitrum,   AaveV3ArbitrumAssets } from "./AaveV3PayloadArbitrum.sol";

contract AaveV3ArbitrumUpdate20230503Payload is AaveV3PayloadArbitrum {
  function capsUpdates() public pure override returns (IEngine.CapsUpdate[] memory) {
    IEngine.CapsUpdate[] memory capsUpdate = new IEngine.CapsUpdate[](1);

    capsUpdate[0] = IEngine.CapsUpdate({
      asset: AaveV3ArbitrumAssets.EURS_UNDERLYING,
      supplyCap: 65000,
      borrowCap: 65000
    });

    return capsUpdate;
  }
}
