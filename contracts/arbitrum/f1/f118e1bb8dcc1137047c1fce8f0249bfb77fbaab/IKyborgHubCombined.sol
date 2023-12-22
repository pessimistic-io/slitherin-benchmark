// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./IKyborgHubPositions.sol";
import "./IKyborgHub.sol";

/// @notice Kyborg hub interface, combining both primary and secondary contract
interface IKyborgHubCombined is IKyborgHub, IKyborgHubPositions {}

