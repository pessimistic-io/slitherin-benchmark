// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.10;

import "./IPositionManager.sol";
import "./IKyborgHubCombined.sol";
import "./ILensBase.sol";

abstract contract LensBase is ILensBase {
    IPositionManager public immutable manager;
    IKyborgHubCombined public immutable hub;

    constructor(address _manager) {
        manager = IPositionManager(_manager);
        hub = IKyborgHubCombined(IPositionManager(_manager).hub());
    }
}

