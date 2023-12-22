// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {IVaultBase} from "./IVaultBase.sol";
import {VaultErrors} from "./VaultErrors.sol";
import {VaultDataTypes} from "./VaultDataTypes.sol";
import {Math} from "./Math.sol";
import {IAddressesRegistry} from "./IAddressesRegistry.sol";
import {IAccessManager} from "./IAccessManager.sol";

/**
 * @title VaultBase
 * @author Souq.Finance
 * @notice The Base contract to be inherited by Vaults
 * @notice License: https://souq-nft-amm-v1.s3.amazonaws.com/LICENSE.md
 */
contract VaultBase is IVaultBase {
    using Math for uint256;

    address public addressesRegistry;
    address public swapRouter;
    VaultDataTypes.VaultData public vaultData;

    /**
     * @dev modifier for when the the msg sender is vault admin in the access manager
     */
    modifier onlyVaultAdmin() {
        require(
            IAccessManager(IAddressesRegistry(addressesRegistry).getAccessManager()).isPoolAdmin(msg.sender),
            VaultErrors.CALLER_NOT_VAULT_ADMIN
        );
        _;
    }

    /**
     * @dev modifier for when the the msg sender is either vault admin or vault operations in the access manager
     */
    modifier onlyVaultAdminOrOperations() {
        require(
            IAccessManager(IAddressesRegistry(addressesRegistry).getAccessManager()).isPoolAdmin(msg.sender) ||
                IAccessManager(IAddressesRegistry(addressesRegistry).getAccessManager()).isPoolOperations(msg.sender),
            VaultErrors.CALLER_NOT_VAULT_ADMIN_OR_OPERATIONS
        );
        _;
    }

    constructor(address _registry) {
        addressesRegistry = _registry;
    }

    function setSwapRouter(address _router) external onlyVaultAdminOrOperations {
        swapRouter = _router;
    }

    function getHardcap() external view returns (uint256) {
        return vaultData.stableHardcap;
    }

    function getUnderlyingTokens() external view returns (address[] memory) {
        return vaultData.VITs;
    }
    
    function getUnderlyingTokenAmounts() external view returns (uint256[] memory) {
        return vaultData.VITAmounts;
    }

    function getLockupTimes() external view returns (uint256[] memory) {
        return vaultData.lockupTimes;
    }

    /// @inheritdoc IVaultBase
    function setFee(VaultDataTypes.VaultFee calldata _newFee) external onlyVaultAdmin {
        vaultData.fee = _newFee;
        emit FeeChanged(_newFee);
    }

    /// @inheritdoc IVaultBase
    function setVaultData(VaultDataTypes.VaultData calldata _newVaultData) external onlyVaultAdmin {
        vaultData = _newVaultData;
        emit VaultDataSet(_newVaultData);
    }
}
