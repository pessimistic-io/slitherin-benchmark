// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./ISavvyTokenParams.sol";
import "./ISavvyErrors.sol";
import "./ISavvyEvents.sol";
import "./ISavvyAdminActions.sol";
import "./IYieldStrategyManagerStates.sol";
import "./IYieldStrategyManagerActions.sol";
import "./Limiters.sol";

/// @title  IYieldStrategyManager
/// @author Savvy DeFi
interface IYieldStrategyManager is
    ISavvyTokenParams,
    ISavvyErrors,
    ISavvyEvents,
    IYieldStrategyManagerStates,
    IYieldStrategyManagerActions
{

}

