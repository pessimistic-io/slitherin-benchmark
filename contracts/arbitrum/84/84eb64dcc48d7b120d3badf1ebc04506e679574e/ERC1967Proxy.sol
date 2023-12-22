// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {ERC1967UpgradeUpgradeable} from "./ERC1967UpgradeUpgradeable.sol";
import {Proxy} from "./Proxy.sol";

/// @dev Proxy container for all upgradeable contracts
contract ERC1967Proxy is Proxy, ERC1967UpgradeUpgradeable {
    /// @dev Initializes the proxy with an implementation contract and encoded function call
    /// @param _logic The implementation address
    /// @param _data The encoded function call
    constructor(address _logic, bytes memory _data) payable {
        _upgradeToAndCall(_logic, _data, false);
    }

    /// @dev The address of the current implementation
    function _implementation() internal view override returns (address) {
        return ERC1967UpgradeUpgradeable._getImplementation();
    }
}

