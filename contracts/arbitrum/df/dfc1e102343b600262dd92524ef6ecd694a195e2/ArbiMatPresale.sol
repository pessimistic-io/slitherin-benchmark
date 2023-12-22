// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ComponentPresale.sol";

contract ArbiMatPresale is ComponentPresale {
    constructor(
        address _addressManagedToken
    ) ComponentPresale(_addressManagedToken, 0.0825 * 10 ** 18, 10_000 * 10 ** 18, 50 * 0.0825 * 10 ** 18) {
        isPurchaseWithoutWlAllowed = false;
        isNoLimitPurchaseAllowed = false;
        isClaimingAllowed = false;
    }
}

