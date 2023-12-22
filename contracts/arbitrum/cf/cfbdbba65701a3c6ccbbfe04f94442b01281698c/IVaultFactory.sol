// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {IAddressesRegistry} from "./IAddressesRegistry.sol";
import {DataTypes} from "./DataTypes.sol";

/**
 * @title IVaultFactory
 * @author Souq.Finance
 * @notice Interface for VaultFactory contract
 * @notice License: https://souq-etf.s3.amazonaws.com/LICENSE.md
 */
interface IVaultFactory {
    /**
     * @dev Emitted when a new vault is deployed using same logic
     * @param user The deployer
     * @param proxy The proxy address deployed
     * @param index The vault index in the factory
     */
    event VaultDeployed(address user, address proxy, uint256 index);
    /**
     * @dev Emitted when the vaults are upgraded to new logic
     * @param admin The admin address
     * @param newImplementation The new implementation logic address
     */
    event VaultsUpgraded(address admin, address newImplementation);
    /**
     * @dev Emitted when the onlyVaultAdminDeployments flag changes which enables admins to deploy only
     * @param admin The admin address
     * @param newStatus The new status
     */
    event DeploymentByVaultAdminOnlySet(address admin, bool newStatus);

    /**
     * @dev This function is called only once to initialize the contract. It sets the initial vault logic contract and fee configuration.
     * @param _vaultLogic The vault logic contract address
     */
    function initialize(address _vaultLogic) external;

    /**
     * @dev This function sets the fee configuration of the contract
     * @return address of the new proxy
     */
    function deployVault(address _feeReceiver) external returns (address);

    /**
     * @dev This function returns the count of vaults created by the factory.
     * @return uint256 the count
     */
    function getVaultsCount() external view returns (uint256);

    /**
     * @dev This function takes an index as a parameter and returns the address of the vault at that index
     * @param index the vault id
     * @return address the proxy address of the vault
     */
    function getVault(uint256 index) external view returns (address);

    /**
     * @dev This function upgrades the vaults to a new logic contract. It is only callable by the upgrader. It increments the vaults version and emits a VaultsUpgraded event.
     * @param newLogic The new logic contract address
     */
    function upgradeVaults(address newLogic) external;

    /**
     * @dev Function to get the version of the vaults
     * @return uint256 version of the vaults. Only incremeted when the beacon is upgraded
     */
    function getVaultsVersion() external view returns (uint256);

    /**
     * @dev Function to get the version of the proxy
     * @return uint256 version of the contract. Only incremeted when the proxy is upgraded
     */
    function getVersion() external view returns (uint256);

    /**
     * @dev This function sets the status of onlyVaultAdminDeployments. It is only callable by the vault admin.
     * @param status The new status
     */
    function setDeploymentByVaultAdminOnly(bool status) external;
}

