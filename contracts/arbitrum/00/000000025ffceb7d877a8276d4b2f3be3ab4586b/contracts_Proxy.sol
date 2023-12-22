// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TransparentUpgradeableProxy} from "./TransparentUpgradeableProxy.sol";

contract Proxy is
    TransparentUpgradeableProxy(msg.sender, tx.origin, new bytes(0))
{}

