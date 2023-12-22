/**
 * Storage specific to the execution facet
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import {IERC20} from "./ERC20_IERC20.sol";
import {ITokenBridge, IPayloadBridge} from "./IBridgeProvider.sol";
import {IDataProvider} from "./IDataProvider.sol";

// Token data
struct Token {
    bytes32 solAddress;
    address localAddress;
    ITokenBridge bridgeProvider;
    
}

struct CoreStorage {
    /**
     * Address of the solana eHXRO program
     */
    bytes32 solanaProgram;
    /**
     * All supported tokens
     */
    bytes32[] allSupportedTokens;
    /**
     * Mapping supported tokens (SOL Address) => Token data
     */
    mapping(bytes32 supportedToken => Token tokenData) tokens;
    /**
     * The address of the bridge provider for bridging plain payload
     */
    IPayloadBridge plainBridgeProvider;
    /**
     * Map user address => nonce
     */
    mapping(address => uint256) nonces;
    /**
     * Chainlink oracle address
     */
    IDataProvider dataProvider;
}

/**
 * The lib to use to retreive the storage
 */
library CoreStorageLib {
    // ======================
    //       STORAGE
    // ======================
    // The namespace for the lib (the hash where its stored)
    bytes32 internal constant STORAGE_NAMESPACE =
        keccak256("diamond.hxro.storage.core.execution");

    // Function to retreive our storage
    function retreive() internal pure returns (CoreStorage storage s) {
        bytes32 position = STORAGE_NAMESPACE;
        assembly {
            s.slot := position
        }
    }
}

