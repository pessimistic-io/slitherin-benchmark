// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.16;

import {IOwnable} from "./IOwnable.sol";

import {ISimpleInitializable} from "./ISimpleInitializable.sol";

import {IAccountWhitelist} from "./IAccountWhitelist.sol";

// solhint-disable-next-line no-empty-blocks
interface IOwnableAccountWhitelist is IAccountWhitelist, IOwnable, ISimpleInitializable {

}

