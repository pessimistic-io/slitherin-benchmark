// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import "./WitnetRequestMalleableBase.sol";

contract WitnetRequestRandomness
    is
        WitnetRequestMalleableBase
{
    constructor() {
        _initialize(hex"0a0f120508021a01801a0210022202100b");
    }
}

