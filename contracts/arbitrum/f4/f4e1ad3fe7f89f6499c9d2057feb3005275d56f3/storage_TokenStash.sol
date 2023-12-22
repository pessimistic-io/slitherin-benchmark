/**
 * Storage for the TokenStash facet
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./Vault.sol";
import "./ERC20.sol";

struct TokenStashStorage {
    /**
     * Nested mapping of
     * Vault address => token address => balance
     */
    mapping(Vault => mapping(ERC20 => uint256)) strategyStashes;
}

/**
 * The lib to use to retreive the storage
 */
library TokenStashStorageLib {
    // The namespace for the lib (the hash where its stored)
    bytes32 internal constant STORAGE_NAMESPACE =
        keccak256("diamond.yieldchain.storage.token_stasher");

    // Function to retreive our storage
    function getTokenStasherStorage()
        internal
        pure
        returns (TokenStashStorage storage s)
    {
        bytes32 position = STORAGE_NAMESPACE;
        assembly {
            s.slot := position
        }
    }

    function addToStrategyStash(
        Vault strategy,
        ERC20 token,
        uint256 amount
    ) internal {
        getTokenStasherStorage().strategyStashes[strategy][token] += amount;
    }

    function removeFromStrategyStash(
        Vault strategy,
        ERC20 token,
        uint256 amount
    ) internal {
        require(
            getTokenStasherStorage().strategyStashes[strategy][token] >= amount,
            "Insufficient Balance To Deduct From Stash"
        );

        getTokenStasherStorage().strategyStashes[strategy][token] -= amount;
    }
}

