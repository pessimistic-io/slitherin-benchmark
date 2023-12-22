// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.4;

import { IGovernable } from "./IGovernable.sol";

import { IClearingHouseActions } from "./IClearingHouseActions.sol";
import { IClearingHouseCustomErrors } from "./IClearingHouseCustomErrors.sol";
import { IClearingHouseEnums } from "./IClearingHouseEnums.sol";
import { IClearingHouseEvents } from "./IClearingHouseEvents.sol";
import { IClearingHouseOwnerActions } from "./IClearingHouseOwnerActions.sol";
import { IClearingHouseStructures } from "./IClearingHouseStructures.sol";
import { IClearingHouseSystemActions } from "./IClearingHouseSystemActions.sol";
import { IClearingHouseView } from "./IClearingHouseView.sol";

interface IClearingHouse is
    IGovernable,
    IClearingHouseEnums,
    IClearingHouseStructures,
    IClearingHouseActions,
    IClearingHouseCustomErrors,
    IClearingHouseEvents,
    IClearingHouseOwnerActions,
    IClearingHouseSystemActions,
    IClearingHouseView
{}

