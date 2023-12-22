// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import { IEntryPoint } from "./IEntryPoint.sol";
import { SimpleAccount } from "./SimpleAccount.sol";

contract TokenPocketAccount is SimpleAccount {

    string public constant VERSION = "1.0.0";

    constructor(IEntryPoint _entryPoint) SimpleAccount(_entryPoint) {

    }

}
