// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IRegistry.sol";

abstract contract Upgradeable is UUPSUpgradeable, OwnableUpgradeable {
    // @address:REGISTRY
    IRegistry constant registry = IRegistry(0x5517dB2A5C94B3ae95D3e2ec12a6EF86aD5db1a5);
    
    function _authorizeUpgrade(address) internal override {
        address upgrader = address(registry) == address(0)
            ? address(0)
            : address(registry.upgrader());
        require(
            upgrader == address(0) ? tx.origin == owner() : msg.sender == upgrader,
            "Sender is not the upgrader"
        );
    }
}
