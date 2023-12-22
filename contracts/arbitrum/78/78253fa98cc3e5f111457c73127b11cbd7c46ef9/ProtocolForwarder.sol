// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Forwarder} from "./Forwarder.sol";

contract ProtocolForwarder is Forwarder {
    constructor() Forwarder() {}
}

