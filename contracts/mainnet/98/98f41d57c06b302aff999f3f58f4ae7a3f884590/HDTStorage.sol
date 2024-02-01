//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IPool.sol";

contract HDTStorage {
    address internal _assetToken;
    uint8 internal _decimals;

    IPool internal _pool;
}

