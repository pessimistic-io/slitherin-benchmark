// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AERC1155Receiver2.sol";
import "./AERC721Receiver2.sol";

abstract contract ANFTReceiver2 is AERC721Receiver2, AERC1155Receiver2 {}

