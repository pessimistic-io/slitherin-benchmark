// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BeaconProxy} from "./BeaconProxy.sol";

contract Proxy is
    BeaconProxy(0x0000000eaAfD44b5123073D71317c2A73e38228d, new bytes(0))
{}

