// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./IKyborgHubBase.sol";
import "./IKyborgHubEvents.sol";
import "./IKyborgHubPositionsActions.sol";
import "./IKyborgHubPositionsView.sol";

interface IKyborgHubPositions is
    IKyborgHubBase,
    IKyborgHubEvents,
    IKyborgHubPositionsActions,
    IKyborgHubPositionsView
{}

