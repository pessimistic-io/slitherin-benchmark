// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.23;

import "./IPlatformPositionHandler.sol";

interface IThetaVaultActionHandler {
    function platform() external view returns (IPlatformPositionHandler);
}

