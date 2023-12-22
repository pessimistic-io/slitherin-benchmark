// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IDeFiBridgeActions.sol";
import "./IDeFiBridgeErrors.sol";
import "./IDeFiBridgeEvents.sol";
import "./IDeFiBridgeState.sol";
import "./IWormholeReceiver.sol";

interface IDeFiBridge is IDeFiBridgeState, IDeFiBridgeActions, IDeFiBridgeEvents, IDeFiBridgeErrors, IWormholeReceiver  {
}
