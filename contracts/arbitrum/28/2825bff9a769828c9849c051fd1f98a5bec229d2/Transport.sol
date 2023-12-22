// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.15;

import { TransportReceive } from "./TransportReceive.sol";
import { TransportStargate } from "./TransportStargate.sol";

contract Transport is TransportReceive, TransportStargate {}

