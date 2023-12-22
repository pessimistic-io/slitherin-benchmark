// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./Ownable.sol";
import "./SafeERC20.sol";

/// @notice One place to manage all Ryze vaults
/// @author https://balance.capital
contract BinaryVaultManager is Ownable {
    /// @dev token => vault
    mapping(address => address) public vaults;

    /// @notice event about new vault
    /// @param vault CA of given vault
    /// @param underlyingToken CA of underlying asset
    /// @param isNewToken create or update
    event VaultAdded(
        address indexed vault,
        address indexed underlyingToken,
        bool isNewToken
    );

    /// @notice add new vault to the manager
    /// @param vault CA of vault
    /// @param underlyingToken CA of underlying asset
    function registerVault(address vault, address underlyingToken)
        external
        onlyOwner
    {
        bool isNew = vaults[underlyingToken] == address(0);
        vaults[underlyingToken] = vault;

        emit VaultAdded(vault, underlyingToken, isNew);
    }
}

