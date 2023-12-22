// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.12;

import "./IStrategyRegistry.sol";

// Factory
import "./ClonesUpgradeable.sol";

// Proxy Support
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./CountersUpgradeable.sol";

// Vault support
import "./IVaultRegistry.sol";
import "./IImplementation.sol";

// Beacon support
import "./BeaconProxy.sol";

// Governance
import { IOrchestrator } from "./IOrchestrator.sol";

// Inheritance
import { InterfaceManager } from "./InterfaceManager.sol";

/// @title A registry for vaults
/// @author Steer Protocol
/// @dev All vaults are created through this contract
contract VaultRegistry is
    Initializable,
    UUPSUpgradeable,
    PausableUpgradeable,
    InterfaceManager
{
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

    // Pause role for disabling vault creation in the event of an emergency
    bytes32 internal constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // Governance role for controlling aspects of the registry
    bytes32 internal constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    // Total vault count
    uint256 public totalVaultCount;

    // Mapping for vaults to their details
    // Vault Address => VaultDetails
    mapping(address => VaultData) internal vaults;

    // Mapping from strategy token ID (Execution Bundle) to list of linked vault IDs
    //  Strategy ID => (VaultId => vault address)
    mapping(uint256 => mapping(uint256 => address)) public linkedVaults;

    // Mapping for strategy token ID to number of vaults created using that strategy.
    mapping(uint256 => uint256) internal linkedVaultCounts;

    //Orchestrator address
    address public orchestrator;

    // Strategy registry address--used for strategy IDs
    IStrategyRegistry public strategyRegistry;

    // Misc addresses--used to point vaults towards the correct contracts.
    address public whitelistRegistry;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer() {}

    /// @dev intializes the vault registry
    /// @param _orchestrator The address of the orchestrator
    /// @param _strategyRegistry The address of the strategy registry
    /// @param _whitelistRegistry Address of whitelist registry which keeps track of whitelist managers and members of whitelisted vaults
    function initialize(
        address _orchestrator,
        address _strategyRegistry,
        address _whitelistRegistry
    ) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();
        __AccessControl_init();
        __Pausable_init();

        require(_strategyRegistry != address(0), "address(0)");
        require(_whitelistRegistry != address(0), "address(0)");
        require(_orchestrator != address(0), "address(0)");
        orchestrator = _orchestrator;
        // Instantiate the strategy registry
        strategyRegistry = IStrategyRegistry(_strategyRegistry);

        // Record misc addresses
        whitelistRegistry = _whitelistRegistry;

        // Access Control Setup
        // Grant pauser, beacon creator, and ERC165 editor roles to deployer for deploying initial beacons
        _setupRole(PAUSER_ROLE, _msgSender());
        _setupRole(BEACON_CREATOR, _msgSender());
        _setupRole(INTERFACE_EDITOR, _msgSender());
        // Grant admin role to deployer but after registering all initial beacons in its script, deployer will revoke all roles granted to self and grant default admin role and above three roles to multisig
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /// @dev Creates a new vault with the given strategy
    /// @dev Registers an execution bundle, mints an NFT and mappings it to execution bundle and it's details.
    /// @param _params is extra parameters in vault.
    /// @param _tokenId is the NFT of the execution bundle this vault will be using. Note that if the given tokenID does not yet exist, the vault will remain inactive.
    /// @param _beaconName beacon identifier of vault type to be created
    /// @param _vaultManager is the address which will manage the vault being created
    /// @dev owner is set as msg.sender.
    function createVault(
        bytes memory _params,
        uint256 _tokenId,
        string memory _beaconName,
        address _vaultManager,
        string memory _payloadIpfs
    ) external whenNotPaused returns (address) {
        //Validate that no strategy exists of the tokenid passed
        strategyRegistry.ownerOf(_tokenId);
        // Retrieve the address for the vault type to be created
        address beaconAddress = beaconAddresses[_beaconName];
        // Make sure that we have a beacon for the provided vault type
        // This ensures that a bad vault type hasn't been provided
        require(beaconAddress != address(0), "Beacon is not present");
        // Create new vault implementation
        BeaconProxy newVault = new BeaconProxy(
            beaconAddress,
            abi.encodeWithSelector(
                IImplementation.initialize.selector,
                _vaultManager,
                orchestrator,
                owner(),
                _params
            )
        );

        // Add beacon type to mapping
        beaconTypes[address(newVault)] = _beaconName;

        // Add enumeration for the vault
        _addLinkedVaultsEnumeration(
            _tokenId,
            address(newVault),
            _payloadIpfs,
            _beaconName
        );

        // Emit vault details
        emit VaultCreated(
            msg.sender,
            address(newVault),
            _beaconName,
            _tokenId,
            _vaultManager
        );

        // Return the address of the new vault
        return address(newVault);
    }

    /// @dev Updates the vault state and emits a VaultStateChanged event
    /// @param _vault The address of the vault
    /// @param _newState The new state of the vault
    /// @dev This function is only available to the registry owner.
    function updateVaultState(
        address _vault,
        VaultState _newState
    ) external onlyOwner {
        vaults[_vault].state = _newState;
        emit VaultStateChanged(_vault, _newState);
    }

    /// @dev Retrieves the creator of a given vault
    /// @param _vault The address of the vault
    /// @return The address of the creator
    function getStrategyCreatorForVault(
        address _vault
    ) external view returns (address) {
        return strategyRegistry.ownerOf(vaults[_vault].tokenId);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /// @dev Pauses the minting of the ERC721 tokens for the vault
    /// @dev This function is only available to the pauser role
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @dev Provides support for vault enumeration
    /// @dev Private function to add a token to this extension's ownership-tracking data structures.
    /// @param _tokenId uint256 ID of the token to be added to the tokens list of the given address
    /// @param _deployedAddress address of the new vault
    function _addLinkedVaultsEnumeration(
        uint256 _tokenId,
        address _deployedAddress,
        string memory _payloadIpfs,
        string memory _beaconName
    ) internal {
        // Get the current count of how many vaults have been created from this strategy.
        uint256 currentCount = linkedVaultCounts[_tokenId];

        // Using _tokenId and count as map keys, add the vault to the list of linked vaults
        linkedVaults[_tokenId][currentCount] = _deployedAddress;

        // Increment the count of how many vaults have been created from a given strategy
        linkedVaultCounts[_tokenId] = currentCount + 1;

        // Store any vault specific data via the _deployedAddress
        vaults[_deployedAddress] = VaultData({
            state: VaultState.PendingThreshold,
            tokenId: _tokenId,
            vaultID: ++totalVaultCount,
            payloadIpfs: _payloadIpfs,
            vaultAddress: _deployedAddress,
            beaconName: _beaconName
        });
    }

    /// @dev Retrieves the details of a given vault by address
    /// @param _address The address of the vault
    /// @return The details of the vault
    function getVaultDetails(
        address _address
    ) public view returns (VaultData memory) {
        return vaults[_address];
    }

    /// @dev Retrieves the vault count by vault token id
    /// @param _tokenId The token id of the vault
    /// @return The count of the vault
    function getVaultCountByStrategyId(
        uint256 _tokenId
    ) public view returns (uint256) {
        return linkedVaultCounts[_tokenId];
    }

    /// @dev Retrieves the vault by vault token id and vault index
    /// @param _tokenId The token id of the vault
    /// @param _vaultId The index of the vault
    /// @return Vault details
    function getVaultByStrategyAndIndex(
        uint256 _tokenId,
        uint256 _vaultId
    ) public view returns (VaultData memory) {
        return vaults[linkedVaults[_tokenId][_vaultId]];
    }
}

