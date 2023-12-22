// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import { Clones } from "./Clones.sol";

import { Vault } from "./Vault.sol";

contract VaultFactory {

    /// ███ Events ███████████████████████████████████████████████████████████

    event VaultCreated(address indexed vault);


    /// ███ Vault creator ████████████████████████████████████████████████████

    function create(
        address _vaultImplementation,
        string memory _name
    ) external {
        address addr = Clones.clone(_vaultImplementation);
        Vault newVault = Vault(addr);
        newVault.initialize(msg.sender, _name);
        emit VaultCreated(addr);
    }
}

