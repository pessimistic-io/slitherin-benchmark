// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeOwnable.sol";
import "./OwnableStorage.sol";

contract Registry is SafeOwnable {
    using OwnableStorage for OwnableStorage.Layout;

    event VaultAdded(Vault);
    event VaultUpdated(Vault, Vault);
    event VaultRemoved(Vault);

    struct Vault {
        address vault;
        address queue;
        address auction;
        address pricer;
    }

    Vault[] public vaults;

    constructor() {
        OwnableStorage.layout().setOwner(msg.sender);
    }

    function length() external view returns (uint256) {
        return vaults.length;
    }

    function add(Vault memory vault) external onlyOwner {
        vaults.push(vault);
        emit VaultAdded(vault);
    }

    function update(uint256 index, Vault memory vault) external onlyOwner {
        emit VaultUpdated(vaults[index], vault);
        vaults[index] = vault;
    }

    function remove(uint256 index) external onlyOwner {
        require(vaults.length > index, "index out of bounds");

        emit VaultRemoved(vaults[index]);

        for (uint256 i = index; i < vaults.length - 1; ++i) {
            vaults[i] = vaults[i + 1];
        }

        vaults.pop();
    }
}

