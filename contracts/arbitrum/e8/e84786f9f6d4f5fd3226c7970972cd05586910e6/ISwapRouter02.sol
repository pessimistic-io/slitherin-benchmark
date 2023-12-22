// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0 <0.9.0;

import "./IImmutableState.sol";
import "./IPeripheryPaymentsWithFeeExtended.sol";

import "./IV2SwapRouter.sol";
import "./IV3SwapRouter.sol";

/// @title Router token swapping functionality
interface ISwapRouter02 is IV2SwapRouter, IV3SwapRouter, IImmutableState, IPeripheryPaymentsWithFeeExtended {

}

