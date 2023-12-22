// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ComponentVestingRefillable.sol";

contract ArbiMatVetsingExternalAirdrops is ComponentVestingRefillable {
    constructor(address _addressManagedToken) ComponentVestingRefillable(_addressManagedToken, 60 hours) {}
}

