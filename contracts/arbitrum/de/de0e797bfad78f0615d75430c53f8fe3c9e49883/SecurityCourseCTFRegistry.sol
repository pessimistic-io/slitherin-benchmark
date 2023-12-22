// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {CTFRegistry} from "./CTFRegistry.sol";

contract SecurityCourseCTFRegistry is CTFRegistry {
    constructor() CTFRegistry("2024 Smart Contract Security Course NFT", "SCSC") {}
}

