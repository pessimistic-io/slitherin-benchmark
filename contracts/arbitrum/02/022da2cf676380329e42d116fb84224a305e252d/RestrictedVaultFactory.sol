// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./VaultFactory.sol";

/// @title Saffron Fixed Income Vault Factory (Restricted)
/// @author psykeeper, supafreq, everywherebagel, maze, rx
/// @notice This factory restricts vault and adapter creation to the factory's owner
contract RestrictedVaultFactory is VaultFactory {
  /// @inheritdoc VaultFactory
  function createVault(uint256 _vaultType, address _adapter) public override onlyOwner {
    super.createVault(_vaultType, _adapter);
  }

  /// @inheritdoc VaultFactory
  function createAdapter(uint256 _adapterType, address _base, bytes calldata _data) public override onlyOwner {
    super.createAdapter(_adapterType, _base, _data);
  }
}

