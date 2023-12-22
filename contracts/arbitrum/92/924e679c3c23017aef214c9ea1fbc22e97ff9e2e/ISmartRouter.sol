// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.17;
pragma abicoder v2;

import {ISwapRouter} from "./ISwapRouter.sol";
import {IPeripheryPayments} from "./IPeripheryPayments.sol";
import {IPeripheryImmutableState} from "./IPeripheryImmutableState.sol";

/// @title Router token swapping functionality
interface ISmartRouter is ISwapRouter, IPeripheryPayments, IPeripheryImmutableState {

}

