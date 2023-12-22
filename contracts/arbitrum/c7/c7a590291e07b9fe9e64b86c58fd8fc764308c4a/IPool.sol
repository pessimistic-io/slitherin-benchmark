// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IPoolActions} from "./IPoolActions.sol";
import {IPoolEvents} from "./IPoolEvents.sol";
import {IPoolStorage} from "./IPoolStorage.sol";

interface IPool is IPoolActions, IPoolEvents, IPoolStorage {}

