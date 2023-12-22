// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IRegistry.sol";

abstract contract Upgradeable is UUPSUpgradeable, OwnableUpgradeable {
    // @address:REGISTRY
    IRegistry constant registry = IRegistry(0xD4DEa29C068ea13EfA6E4Dd2FADB14aE2353A541);
    
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
