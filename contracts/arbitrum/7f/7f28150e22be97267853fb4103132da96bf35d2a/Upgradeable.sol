// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IRegistry.sol";

abstract contract Upgradeable is UUPSUpgradeable, OwnableUpgradeable {
    // @address:REGISTRY
    IRegistry constant registry = IRegistry(0xe8258b0003CB159c75bfc2bC2D079d12E3774a80);
    
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
