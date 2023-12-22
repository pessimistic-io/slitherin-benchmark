// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./EnumerableSet.sol";
import "./Ownable.sol";

/// @title SteakHut Liquidity Registry
/// @author SteakHut
/// @notice Contract used to register new Vaults into registry.
contract SteakHutLiquidtyRegistry is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(address => bool) public whiteListedVault;
    //addresses of all vaults
    EnumerableSet.AddressSet private allVaults;

    /// -----------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------
    event VaultAdded(address vaultAddress, bool isWhitelisted);
    event VaultWhitelisted(address vaultAddress, bool isWhitelisted);

    /// @notice Constructor
    constructor() {}

    /// @notice Add a new Liquidity Vault to registry
    /// @param _vault address for new liquidity vault
    function addVault(
        address _vault
    ) external onlyOwner returns (address vaultAddress) {
        require(
            allVaults.add(_vault),
            "LiquidityRegistry: addVault, Vault already added"
        );

        emit VaultAdded(_vault, false);
        return _vault;
    }

    /// @notice whitelist or remove whitelist of vault
    /// @param _vault address for new liquidity vault
    function whitelistVault(
        address _vault,
        bool _isWhitelisted
    ) external onlyOwner {
        whiteListedVault[_vault] = _isWhitelisted;
        emit VaultWhitelisted(_vault, _isWhitelisted);
    }
}

