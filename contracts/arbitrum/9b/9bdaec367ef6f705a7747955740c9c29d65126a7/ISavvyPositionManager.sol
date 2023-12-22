// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./ISavvyActions.sol";
import "./ISavvyAdminActions.sol";
import "./ISavvyErrors.sol";
import "./ISavvyImmutables.sol";
import "./ISavvyEvents.sol";
import "./ISavvyState.sol";

/// @title  ISavvyPositionManager
/// @author Savvy DeFi
interface ISavvyPositionManager is
    ISavvyActions,
    ISavvyAdminActions,
    ISavvyErrors,
    ISavvyImmutables,
    ISavvyEvents,
    ISavvyState
{

}

