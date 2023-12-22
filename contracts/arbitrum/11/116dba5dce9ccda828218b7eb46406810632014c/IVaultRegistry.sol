// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.12;
pragma abicoder v2; //Used this because function getAssetSymbols uses string[2]

import { IStrategyRegistry } from "./IStrategyRegistry.sol";
import { IOrchestrator } from "./IOrchestrator.sol";

interface IVaultRegistry {
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

    /// @dev Vault creation event
    /// @param deployer The address of the deployer
    /// @param vault The address of the vault
    /// @param tokenId ERC721 token id for the vault
    /// @param vaultManager is the address which will manage the vault being created
    event VaultCreated(
        address deployer,
        address vault,
        string beaconName,
        uint256 indexed tokenId,
        address vaultManager
    );

    /// @dev Vault state change event
    /// @param vault The address of the vault
    /// @param newState The new state of the vault
    event VaultStateChanged(address indexed vault, VaultState newState);

    // Total vault count.
    function totalVaultCount() external view returns (uint256);

    function whitelistRegistry() external view returns (address);

    function orchestrator() external view returns (IOrchestrator);

    function beaconAddresses(string calldata) external view returns (address);

    function beaconTypes(address) external view returns (string memory);

    // Interface for the strategy registry
    function strategyRegistry() external view returns (IStrategyRegistry);

    /// @dev intializes the vault registry
    /// @param _orchestrator The address of the orchestrator
    /// @param _strategyRegistry The address of the strategy registry
    /// @param _whitelistRegistry The address of the whitelist registry
    function initialize(
        address _orchestrator,
        address _strategyRegistry,
        address _whitelistRegistry
    ) external;

    /// @dev Registers a beacon associated with a new vault type
    /// @param _name The name of the vault type this beacon will be using
    /// @param _address The address of the upgrade beacon
    /// @param _ipfsConfigForBeacon IPFS hash for the config of this beacon
    function registerBeacon(
        string calldata _name,
        address _address,
        string calldata _ipfsConfigForBeacon
    ) external;

    /// @dev Deploy new beacon for a new vault type AND register it
    /// @param _address The address of the implementation for the beacon
    /// @param _name The name of the beacon (identifier)
    /// @param _ipfsConfigForBeacon IPFS hash for the config of this beacon
    function deployAndRegisterBeacon(
        address _address,
        string calldata _name,
        string calldata _ipfsConfigForBeacon
    ) external returns (address);

    /// @dev Removes a beacon associated with a vault type
    /// @param _name The name of the beacon (identifier)
    /// @dev This will stop the creation of more vaults of the type provided
    function deregisterBeacon(string calldata _name) external;

    /// @dev Creates a new vault with the given strategy
    /// @dev Registers an execution bundle, mints an NFT and mappings it to execution bundle and it's details.
    /// @param _params is extra parameters in vault.
    /// @param _tokenId is the NFT of the execution bundle this vault will be using.
    /// @param _beaconName beacon identifier of vault type to be created
    /// @dev owner is set as msg.sender.
    function createVault(
        bytes memory _params,
        uint256 _tokenId,
        string memory _beaconName,
        address _vaultManager,
        string memory strategyData
    ) external returns (address);

    /// @dev Updates the vault state and emits a VaultStateChanged event
    /// @param _vault The address of the vault
    /// @param _newState The new state of the vault
    /// @dev This function is only available to the registry owner
    function updateVaultState(address _vault, VaultState _newState) external;

    /// @dev Retrieves the creator of a given vault
    /// @param _vault The address of the vault
    /// @return The address of the creator
    function getStrategyCreatorForVault(
        address _vault
    ) external view returns (address);

    /// @dev This function is only available to the pauser role
    function pause() external;

    function unpause() external;

    /// @dev Retrieves the details of a given vault by address
    /// @param _address The address of the vault
    /// @return The details of the vault
    function getVaultDetails(
        address _address
    ) external view returns (VaultData memory);

    /// @dev Retrieves the vault count by vault token id
    /// @param _tokenId The token id of the vault
    /// @return The count of the vault
    function getVaultCountByStrategyId(
        uint256 _tokenId
    ) external view returns (uint256);

    /// @dev Retrieves the vault by vault token id and vault index
    /// @param _tokenId The token id of the vault
    /// @param _vaultId The index of the vault
    /// @return Vault details
    function getVaultByStrategyAndIndex(
        uint256 _tokenId,
        uint256 _vaultId
    ) external view returns (VaultData memory);
}

