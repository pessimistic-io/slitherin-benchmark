pragma solidity >=0.8.19;

import "./UUPSProxyWithOwner.sol";

/**
 * Voltz V2 Periphery Proxy Contract
 */
contract PeripheryProxy is UUPSProxyWithOwner {
    // solhint-disable-next-line no-empty-blocks
    constructor(address firstImplementation, address initialOwner)
        UUPSProxyWithOwner(firstImplementation, initialOwner)
    {}
}

