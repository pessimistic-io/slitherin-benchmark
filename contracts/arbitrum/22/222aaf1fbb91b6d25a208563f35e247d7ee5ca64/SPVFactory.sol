// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./PendingOwnable.sol";

import "./SPVault.sol";
import "./ISPVFactory.sol";
import "./ImmutableClone.sol";

contract SPVFactory is ISPVFactory, PendingOwnable {
    address private _defaultManager;

    mapping(ILBPair => address[]) private _pairToVaults;
    address[] private _allVaults;

    address private _vaultImplementation;

    /**
     * @notice Returns the default manager address of the vaults
     * @return The default manager address
     */
    function getDefaultManager() external view override returns (address) {
        return _defaultManager;
    }

    /**
     * @notice Returns the vault implementation address
     * @return The vault implementation address
     */
    function getVaultImplementation() external view override returns (address) {
        return _vaultImplementation;
    }

    /**
     * @notice Returns the vaults for a given pair
     * @param pair The pair to get the vaults for
     * @return The vaults for the given pair
     */
    function getVaults(ILBPair pair) external view override returns (address[] memory) {
        return _pairToVaults[pair];
    }

    /**
     * @notice Returns the vault at index id
     * @param id The index
     * @return The vault at index id
     */
    function getVaultAt(uint256 id) external view override returns (address) {
        return _allVaults[id];
    }

    /**
     * @notice Returns the number of vault
     * @return The number of vault created using the SPVFactory
     */
    function getNumberOfVault() external view returns (uint256) {
        return _allVaults.length;
    }

    /**
     * @notice Sets the vault implementation address
     * @param vaultImplementation The vault implementation address
     */
    function setVaultImplementation(address vaultImplementation) external override onlyOwner {
        require(_vaultImplementation != vaultImplementation, "SPVFactory: Same implementation");
        _vaultImplementation = vaultImplementation;

        emit VaultImplementationSet(vaultImplementation);
    }

    /**
     * @notice Sets the default manager address
     * @param defaultManager The default manager address
     */
    function setDefaultManager(address defaultManager) external override onlyOwner {
        require(_defaultManager != defaultManager, "SPVFactory: Same manager");
        _defaultManager = defaultManager;

        emit DefaultManagerSet(defaultManager);
    }

    /**
     * @notice Creates a new vault for a given pair
     * @param pair The pair to create the vault for
     * @return vault The address of the new vault
     */
    function createSPVault(ILBPair pair) external override onlyOwner returns (address vault) {
        address vaultImplementation = _vaultImplementation;
        require(vaultImplementation != address(0), "SPVFactory: Implementation not set");

        uint256 id = _pairToVaults[pair].length;

        bytes32 salt = keccak256(abi.encodePacked(address(pair), id));
        bytes memory data = abi.encodePacked(address(pair), address(pair.tokenX()), address(pair.tokenY()));

        vault = ImmutableClone.cloneDeterministic(_vaultImplementation, data, salt);

        _pairToVaults[pair].push(vault);
        _allVaults.push(vault);

        emit SPVaultCreated(vault, pair, id);
    }
}

