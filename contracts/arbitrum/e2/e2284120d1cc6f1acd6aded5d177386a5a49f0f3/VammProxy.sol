//SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "./UUPSProxyWithOwner.sol";

/**
 * Voltz V2 VAMM Proxy Contract
 */
contract VammProxy is UUPSProxyWithOwner {
    // solhint-disable-next-line no-empty-blocks
    constructor(address firstImplementation, address initialOwner)
        UUPSProxyWithOwner(firstImplementation, initialOwner)
    {}
}

