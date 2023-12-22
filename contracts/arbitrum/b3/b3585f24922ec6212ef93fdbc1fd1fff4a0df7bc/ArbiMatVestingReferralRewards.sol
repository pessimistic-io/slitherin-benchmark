// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ComponentVestingRefillable.sol";

contract ArbiMatVestingReferralRewards is ComponentVestingRefillable {
    constructor(address _addressManagedToken) ComponentVestingRefillable(_addressManagedToken, 24 hours) {}
}

