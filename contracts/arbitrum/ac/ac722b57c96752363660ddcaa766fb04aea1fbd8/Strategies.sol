/**
 * Strategies storage for the YC Diamond
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./Vault.sol";

/**
 * Represents a strategy's state/settings
 */
struct StrategyState {
    /**
     * Whether it's registered or not (used to verify if a strategy exists)
     */
    bool registered;
    /**
     * The strategy's gas balance in WEI
     */
    uint256 gasBalanceWei;
}

struct StrategiesStorage {
    /**
     * An array of strategies (to make the mapping iterable)
     */
    Vault[] strategies;
    /**
     * @notice
     * Mapping strategies => their corresponding settings
     */
    mapping(Vault => StrategyState) strategiesState;
    /**
     * Map strategies => operation idxs => deposited gas (WEI)
     */
    mapping(Vault => mapping(uint256 => uint256)) strategyOperationsGas;
}

/**
 * The lib to use to retreive the storage
 */
library StrategiesStorageLib {
    // The namespace for the lib (the hash where its stored)
    bytes32 internal constant STORAGE_NAMESPACE =
        keccak256("diamond.yieldchain.storage.strategies");

    // Function to retreive our storage
    function retreive() internal pure returns (StrategiesStorage storage s) {
        bytes32 position = STORAGE_NAMESPACE;
        assembly {
            s.slot := position
        }
    }
}

