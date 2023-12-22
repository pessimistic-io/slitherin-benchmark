//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import "./Vault1155.sol";
import "./VaultDataTypes.sol";
import {IAccessManager} from "./IAccessManager.sol";
import {IAddressesRegistry} from "./IAddressesRegistry.sol";
import {ProxyBeaconDeployer} from "./ProxyBeaconDeployer.sol";
import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";
import {VaultErrors} from "./VaultErrors.sol";
import {IVaultFactory} from "./IVaultFactory.sol";
import {IVault1155} from "./IVault1155.sol";

/**
 * @title VaultFactory.sol
 * @author Souq.Finance
 * @notice This contract deploys and manages Vault contracts.
 * @notice License: https://souq-etf.s3.amazonaws.com/LICENSE.md
 */

contract VaultFactory is IVaultFactory, Initializable, UUPSUpgradeable, ProxyBeaconDeployer {
    address private vaultLogic;
    uint256 public version;
    uint256 public vaultsVersion;
    bool public onlyVaultAdminDeployments;
    address[] public vaults;
    IAddressesRegistry public immutable addressesRegistry;
    uint256[50] private __gap;

    constructor(address registry) {
        require(registry != address(0), VaultErrors.ADDRESS_IS_ZERO);
        addressesRegistry = IAddressesRegistry(registry);
    }

    function initialize(address _vaultLogic) external initializer onlyUpgrader {
        require(_vaultLogic != address(0), VaultErrors.ADDRESS_IS_ZERO);
        __UUPSUpgradeable_init();
        vaultLogic = _vaultLogic;
        onlyVaultAdminDeployments = false;
        version = 1;
        vaultsVersion = 1;
    }

    /**
     * @dev modifier to check if the msg sender has role upgrader in the access manager
     */
    modifier onlyUpgrader() {
        require(IAccessManager(addressesRegistry.getAccessManager()).isUpgraderAdmin(msg.sender), VaultErrors.CALLER_NOT_UPGRADER);
        _;
    }
    /**
     * @dev modifier to check if the msg sender has role pool admin in the access manager
     */
    modifier onlyVaultAdmin() {
        require(IAccessManager(addressesRegistry.getAccessManager()).isPoolAdmin(msg.sender), VaultErrors.CALLER_IS_NOT_VAULT_ADMIN);
        _;
    }
    /**
     * @dev modifier to check if onlyVaultAdminDeployments is true and the msg sender has role pool admin in the access manager
     */
    modifier onlyDeployer() {
        if (onlyVaultAdminDeployments) {
            require(IAccessManager(addressesRegistry.getAccessManager()).isPoolAdmin(msg.sender), VaultErrors.CALLER_NOT_DEPLOYER);
        }
        _;
    }

    /// @inheritdoc IVaultFactory
    function deployVault(address _feeReceiver) external onlyDeployer returns (address) {
        require(_feeReceiver != address(0), VaultErrors.ADDRESS_IS_ZERO);
        address proxy = deployBeaconProxy(vaultLogic, "");
        IVault1155(proxy).initialize(address(this), _feeReceiver);
        vaults.push(proxy);
        emit VaultDeployed(msg.sender, proxy, vaults.length - 1);
        return proxy;
    }

    /// @inheritdoc IVaultFactory
    function getVault(uint256 index) external view returns (address) {
        return vaults[index];
    }

    /// @inheritdoc IVaultFactory
    function getVaultsCount() external view returns (uint256) {
        return vaults.length;
    }

    /// @inheritdoc IVaultFactory
    function upgradeVaults(address newLogic) external onlyUpgrader {
        require(newLogic != address(0), VaultErrors.ADDRESS_IS_ZERO);
        emit VaultsUpgraded(msg.sender, newLogic);
        vaultLogic = newLogic;
        //Change beacon logic
        upgradeBeacon(newLogic);
        ++vaultsVersion;
    }

    /// @inheritdoc IVaultFactory
    function getVaultsVersion() external view returns (uint256) {
        return vaultsVersion;
    }

    /// @inheritdoc IVaultFactory
    function getVersion() external view returns (uint256) {
        return version;
    }

    /// @inheritdoc IVaultFactory
    function setDeploymentByVaultAdminOnly(bool status) external onlyVaultAdmin {
        onlyVaultAdminDeployments = status;
        emit DeploymentByVaultAdminOnlySet(msg.sender, status);
    }

    /**
     * @dev Internal function to permit the upgrade of the proxy.
     * @param newImplementation The new implementation contract address used for the upgrade.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyUpgrader {
        require(newImplementation != address(0), VaultErrors.ADDRESS_IS_ZERO);
        ++version;
    }
}

