// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

interface IVaultRegistry {
    // Enumerations
    enum TradeSide {
        Buy,
        Sell,
        Both
    }

    enum OptionType {
        Call,
        Put,
        Both
    }

    // Structs
    struct Vault {
        address vault;
        address asset;
        bytes32 vaultType;
        TradeSide side;
        OptionType optionType;
    }

    struct TokenPair {
        address base;
        address quote;
        address oracleAdapter;
    }

    // Events
    event VaultImplementationSet(bytes32 indexed vaultType, address implementation);

    event VaultAdded(
        address indexed vault,
        address indexed asset,
        bytes32 vaultType,
        TradeSide side,
        OptionType optionType
    );
    event VaultRemoved(address indexed vault);
    event VaultUpdated(
        address indexed vault,
        address indexed asset,
        bytes32 vaultType,
        TradeSide side,
        OptionType optionType
    );
    event SupportedTokenPairAdded(
        address indexed vault,
        address indexed base,
        address indexed quote,
        address oracleAdapter
    );
    event SupportedTokenPairRemoved(
        address indexed vault,
        address indexed base,
        address indexed quote,
        address oracleAdapter
    );

    /// @notice Gets the total number of vaults in the registry.
    /// @return The total number of vaults in the registry.
    function getNumberOfVaults() external view returns (uint256);

    /// @notice Adds a vault to the registry.
    /// @param vault The proxy address of the vault.
    /// @param asset The address for the token deposited in the vault.
    /// @param vaultType The type of the vault.
    /// @param side The trade side of the vault.
    /// @param optionType The option type of the vault.
    function addVault(address vault, address asset, bytes32 vaultType, TradeSide side, OptionType optionType) external;

    /// @notice Removes a vault from the registry.
    /// @param vault The proxy address of the vault.
    function removeVault(address vault) external;

    /// @notice Returns whether the given address is a vault
    /// @param vault The address to check
    /// @return Whether the given address is a vault
    function isVault(address vault) external view returns (bool);

    /// @notice Updates a vault in the registry.
    /// @param vault The proxy address of the vault.
    /// @param asset The address for the token deposited in the vault.
    /// @param vaultType The type of the vault.
    /// @param side The trade side of the vault.
    /// @param optionType The option type of the vault.
    function updateVault(
        address vault,
        address asset,
        bytes32 vaultType,
        TradeSide side,
        OptionType optionType
    ) external;

    /// @notice Adds a set of supported token pairs to the vault.
    /// @param vault The proxy address of the vault.
    /// @param tokenPairs The token pairs to add.
    function addSupportedTokenPairs(address vault, TokenPair[] memory tokenPairs) external;

    /// @notice Removes a set of supported token pairs from the vault.
    /// @param vault The proxy address of the vault.
    /// @param tokenPairsToRemove The token pairs to remove.
    function removeSupportedTokenPairs(address vault, TokenPair[] memory tokenPairsToRemove) external;

    /// @notice Gets the vault at the specified by the proxy address.
    /// @param vault The proxy address of the vault.
    /// @return The vault associated with the proxy address.
    function getVault(address vault) external view returns (Vault memory);

    /// @notice Gets the token supports supported for trading within the vault.
    /// @param vault The proxy address of the vault.
    /// @return The token pairs supported for trading within the vault.
    function getSupportedTokenPairs(address vault) external view returns (TokenPair[] memory);

    /// @notice Gets all vaults in the registry.
    /// @return All vaults in the registry.
    function getVaults() external view returns (Vault[] memory);

    /// @notice Gets all vaults with trade side `side` and option type `optionType`.
    /// @param assets The accepted assets (empty list for all assets).
    /// @param side The trade side.
    /// @param optionType The option type.
    /// @return All vaults meeting all of the passed filter criteria.
    function getVaultsByFilter(
        address[] memory assets,
        TradeSide side,
        OptionType optionType
    ) external view returns (Vault[] memory);

    /// @notice Gets all vaults with `asset` as their deposit token.
    /// @param asset The desired asset.
    /// @return All vaults with `asset` as their deposit token.
    function getVaultsByAsset(address asset) external view returns (Vault[] memory);

    /// @notice Gets all vaults with `tokenPair` in their trading set.
    /// @param tokenPair The desired token pair.
    /// @return All vaults with `tokenPair` in their trading set.
    function getVaultsByTokenPair(TokenPair memory tokenPair) external view returns (Vault[] memory);

    /// @notice Gets all vaults with trade side `side`.
    /// @param side The trade side.
    /// @return All vaults with trade side `side`.
    function getVaultsByTradeSide(TradeSide side) external view returns (Vault[] memory);

    /// @notice Gets all vaults with option type `optionType`.
    /// @param optionType The option type.
    /// @return All vaults with option type `optionType`.
    function getVaultsByOptionType(OptionType optionType) external view returns (Vault[] memory);

    /// @notice Gets all the vaults of type `vaultType`.
    /// @param vaultType The vault type.
    /// @return All the vaults of type `vaultType`.
    function getVaultsByType(bytes32 vaultType) external view returns (Vault[] memory);

    /// @notice Gets the implementation for the vaultType.
    /// @param vaultType The vault type.
    /// @return The implementation address.
    function getImplementation(bytes32 vaultType) external view returns (address);

    /// @notice Sets the implementation for the vaultType.
    /// @param vaultType The vault type.
    /// @param implementation The implementation contract address
    function setImplementation(bytes32 vaultType, address implementation) external;
}

