// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {IVaultBase} from "./IVaultBase.sol";
import {VaultErrors} from "./VaultErrors.sol";
import {VaultDataTypes} from "./VaultDataTypes.sol";
import {Math} from "./Math.sol";
import {IAddressesRegistry} from "./IAddressesRegistry.sol";
import {IAccessManager} from "./IAccessManager.sol";
import "./console.sol";
/**
 * @title VaultBase
 * @author Souq.Finance
 * @notice The Base contract to be inherited by Vaults
 * @notice License: https://souq-etf.s3.amazonaws.com/LICENSE.md
 */
contract VaultBase is IVaultBase {
    using Math for uint256;

    address public immutable addressesRegistry;
    VaultDataTypes.VaultData public vaultData;
    uint256[50] private __gap;

    /**
     * @dev modifier for when the the msg sender is vault admin in the access manager
     */
    modifier onlyVaultAdmin() {
        require(
            IAccessManager(IAddressesRegistry(addressesRegistry).getAccessManager()).isPoolAdmin(msg.sender),
            VaultErrors.CALLER_IS_NOT_VAULT_ADMIN
        );
        _;
    }

    /**
     * @dev modifier for when the the msg sender is either vault admin or vault operations in the access manager
     */
    modifier onlyVaultAdminOrOperations() {
        console.log("addressesRegistry: ", addressesRegistry);
        require(
            IAccessManager(IAddressesRegistry(addressesRegistry).getAccessManager()).isPoolAdmin(msg.sender) ||
                IAccessManager(IAddressesRegistry(addressesRegistry).getAccessManager()).isPoolOperations(msg.sender),
            VaultErrors.CALLER_IS_NOT_VAULT_ADMIN_OR_OPERATIONS
        );
        _;
    }

    constructor(address _registry) {
        require(_registry != address(0), VaultErrors.ADDRESS_IS_ZERO);
        addressesRegistry = _registry;
    }

    /**
     * @dev Retrieves the hardcap of the vault.
     * @return The hardcap value.
     */
    /// @inheritdoc IVaultBase

    function getHardcap() external view returns (uint256) {
        return vaultData.stableHardcap;
    }

    /**
     * @dev Retrieves the addresses of underlying tokens.
     * @return An array of underlying token addresses.
     */
    /// @inheritdoc IVaultBase
    function getUnderlyingTokens() external view returns (address[] memory) {
        return vaultData.VITs;
    }

    /**
     * @dev Retrieves the amounts of underlying tokens.
     * @return An array of underlying token amounts.
     */
     /// @inheritdoc IVaultBase
    function getUnderlyingTokenAmounts() external view returns (uint256[] memory) {
        return vaultData.VITAmounts;
    }

    /**
     * @dev Retrieves the lockup times for the vault.
     * @return An array of lockup times.
     */
    function getLockupTimes() external view returns (uint256[] memory) {
        return vaultData.lockupTimes;
    }

    /**
     * @dev Sets the fee for the vault.
     * @param _newFee The new fee configuration.
     */
    /// @inheritdoc IVaultBase
    function setFee(VaultDataTypes.VaultFee calldata _newFee) external onlyVaultAdmin {
        vaultData.fee = _newFee;
        emit FeeChanged(_newFee);
    }

    /**
     * @dev Sets the vault data for the vault.
     * @param _newVaultData The new vault data.
     */
    /// @inheritdoc IVaultBase
    function setVaultData(VaultDataTypes.VaultData calldata _newVaultData) external onlyVaultAdmin {
        require(_newVaultData.VITs.length == _newVaultData.VITAmounts.length, VaultErrors.ARRAY_NOT_SAME_LENGTH);
        vaultData = _newVaultData;
        emit VaultDataSet(_newVaultData);
    }
}

