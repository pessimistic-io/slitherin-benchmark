// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ComponentLockerSwapper.sol";

contract ArbiMatLockerSwapperBdsm is ComponentLockerSwapper {
    constructor(
        address _addressManagedToken
    ) ComponentLockerSwapper(address(0x8F408ff2D5353CCfABafbe36105ACC691344d41a), _addressManagedToken) {}
}

