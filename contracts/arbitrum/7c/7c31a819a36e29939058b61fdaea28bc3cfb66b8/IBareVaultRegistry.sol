// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.6;
pragma abicoder v2;

/**
 * Used only as a 0.7.6 registry for the UniLiquidityManager.
 */
interface IBareVaultRegistry {
    /**
     * PendingApproval: strategy is submitted but has not yet been approved by the owner
     * PendingThreshold: strategy is approved but has not yet reached the threshold of TVL required
     * Paused: strategy was active but something went wrong, so now it's paused
     * Active: strategy is active and can be used
     * Retired: strategy is retired and can no longer be used
     */
    enum VaultState {
        PendingApproval,
        PendingThreshold,
        Paused,
        Active,
        Retired
    }

    /**
     * @dev all necessary data for vault. Name and symbol are stored in vault's ERC20. Owner is stored with tokenId in StrategyRegistry.
     * tokenId: NFT identifier number
     * vaultAddress: address of vault this describes
     * state: state of the vault.
     */
    struct VaultData {
        VaultState state;
        uint256 tokenId; //NFT ownership of this vault and all others that use vault's exec bundle
        uint256 vaultID; //unique identifier for this vault and strategy token id
        string payloadIpfs;
        address vaultAddress;
        string beaconName;
    }

    /// @notice Retrieves the creator of a given vault
    /// @param _vault The address of the vault
    /// @return The address of the creator
    function getStrategyCreatorForVault(
        address _vault
    ) external view returns (address);

    //Total vault count
    function totalVaultCount() external view returns (uint256);

    function whitelistRegistry() external view returns (address);

    function doISupportInterface(
        bytes4 interfaceId
    ) external view returns (bool);

    /// @dev Retrieves the details of a given vault by address
    /// @param _address The address of the vault
    /// @return The details of the vault
    function getVaultDetails(
        address _address
    ) external view returns (VaultData memory);
}

