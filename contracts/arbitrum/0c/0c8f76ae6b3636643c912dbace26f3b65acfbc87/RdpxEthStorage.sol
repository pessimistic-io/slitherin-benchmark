// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {UserLPStorage} from "./UserLPStorage.sol";

contract RdpxEthStorage is UserLPStorage {
    constructor(address _lpToken) UserLPStorage(_lpToken) {}
}

