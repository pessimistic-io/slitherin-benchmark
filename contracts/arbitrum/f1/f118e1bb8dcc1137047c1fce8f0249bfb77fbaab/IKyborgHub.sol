// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./IKyborgHubBase.sol";
import "./IKyborgHubEvents.sol";
import "./IKyborgHubActions.sol";
import "./IKyborgHubView.sol";

interface IKyborgHub is IKyborgHubBase, IKyborgHubEvents, IKyborgHubActions, IKyborgHubView {}

