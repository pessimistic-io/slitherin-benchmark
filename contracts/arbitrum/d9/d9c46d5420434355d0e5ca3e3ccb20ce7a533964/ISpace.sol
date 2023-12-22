// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { ISpaceState } from "./ISpaceState.sol";
import { ISpaceActions } from "./ISpaceActions.sol";
import { ISpaceOwnerActions } from "./ISpaceOwnerActions.sol";
import { ISpaceEvents } from "./ISpaceEvents.sol";
import { ISpaceErrors } from "./ISpaceErrors.sol";

/// @title Space Interface
// solhint-disable-next-line no-empty-blocks
interface ISpace is ISpaceState, ISpaceActions, ISpaceOwnerActions, ISpaceEvents, ISpaceErrors {

}

