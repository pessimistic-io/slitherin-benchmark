// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IAlgebraPoolState} from "./IAlgebraPoolState.sol";
import {IAlgebraPoolActions} from "./IAlgebraPoolActions.sol";
import {IAlgebraPoolImmutables} from "./IAlgebraPoolImmutables.sol";

/**
 * @title The interface for a Algebra Pool
 * @dev The pool interface is broken up into many smaller pieces.
 * Credit to Uniswap Labs under GPL-2.0-or-later license:
 * https://github.com/Uniswap/v3-core/tree/main/contracts/interfaces
 */
interface IAlgebraPool is
  IAlgebraPoolState,
  IAlgebraPoolActions,
  IAlgebraPoolImmutables
{
  // used only for combining interfaces
}

