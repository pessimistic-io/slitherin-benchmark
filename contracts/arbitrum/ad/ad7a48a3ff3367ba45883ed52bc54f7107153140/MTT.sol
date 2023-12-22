// SPDX-License-Identifier: MIT
// Metaline Contracts (MTT.sol)

pragma solidity ^0.8.0;

import "./CappedERC20.sol";

// Metaline Token
contract MTT is CappedERC20 {

    constructor()
        CappedERC20("MetaLine Token", "MTT", 300000000000000000000000000)
    {

    }
}
