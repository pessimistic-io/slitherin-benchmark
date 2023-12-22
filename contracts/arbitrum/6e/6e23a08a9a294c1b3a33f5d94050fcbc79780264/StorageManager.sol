/**
 * Read from & Write to core storage
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import {AccessControlled} from "./AccessControl.sol";
import {IERC20} from "./IERC20.sol";
import {ITokenBridge} from "./IBridgeProvider.sol";
import {IDataProvider} from "./IDataProvider.sol";
import "./Core.sol";
import "./Main.sol";

contract StorageManagerFacet is AccessControlled {
    // ==============
    //     READ
    // ==============
    /**
     * Get all supported tokens
     * @return supportedTokens
     */
    function getSupportedTokens()
        external
        view
        returns (bytes32[] memory supportedTokens)
    {
        supportedTokens = CoreStorageLib.retreive().allSupportedTokens;
    }

    /**
     * Get Token struct data of a Solana token
     * @param solToken - Address of the solana token
     * @return tokenData - Data of the token
     */
    function getTokenData(
        bytes32 solToken
    ) external view returns (Token memory tokenData) {
        tokenData = CoreStorageLib.retreive().tokens[solToken];
    }

    /**
     * Get source token of solana token
     */
    function getSourceToken(
        bytes32 destToken
    ) external view returns (address srcToken) {
        srcToken = CoreStorageLib.retreive().tokens[destToken].localAddress;
    }

    /**
     * Get data provider
     */
    function getDataProvider()
        external
        view
        returns (IDataProvider dataProvider)
    {
        dataProvider = IDataProvider(CoreStorageLib.retreive().dataProvider);
    }

    /**
     * Get a token's bridge provider
     */
    function getTokenBridgeProvider(
        bytes32 token
    ) external view returns (ITokenBridge bridgeProvider) {
        bridgeProvider = CoreStorageLib.retreive().tokens[token].bridgeProvider;
        require(
            address(bridgeProvider) != address(0),
            "Unsupported Bridge Provider"
        );
    }

    /**
     *  Get the solana program address (in bytes32)
     */
    function getSolanaProgram() external view returns (bytes32 solanaProgram) {
        solanaProgram = CoreStorageLib.retreive().solanaProgram;
    }

    /**
     * Get a user's nonce
     */
    function getUserNonce(address user) external view returns (uint256 nonce) {
        nonce = CoreStorageLib.retreive().nonces[user];
    }

    function getPayloadBridgeProvider()
        external
        view
        returns (IPayloadBridge bridgeProvider)
    {
        bridgeProvider = CoreStorageLib.retreive().plainBridgeProvider;
    }

    // ==============
    //     WRITE
    // ==============
    /**
     * Add a token's bridge selector
     * @param token - The token's address
     * @param bridgeProvider - The bridge provider
     */
    function addToken(
        address token,
        bytes32 solToken,
        ITokenBridge bridgeProvider
    ) external onlyOwner {
        CoreStorage storage coreStorage = CoreStorageLib.retreive();

        require(
            address(coreStorage.tokens[solToken].bridgeProvider) == address(0),
            "Bridge Provider Already Added. Use updateTokenBridge"
        );

        coreStorage.tokens[solToken] = Token({
            solAddress: solToken,
            localAddress: token,
            bridgeProvider: bridgeProvider
        });
        coreStorage.allSupportedTokens.push(solToken);
    }

    function updateTokenBridgeProvider(
        bytes32 solToken,
        ITokenBridge bridgeProvider
    ) external onlyOwner {
        CoreStorage storage coreStorage = CoreStorageLib.retreive();

        require(
            address(coreStorage.tokens[solToken].bridgeProvider) != address(0),
            "Bridge Provider Already Added. Use updateTokenBridge"
        );

        coreStorage.tokens[solToken].bridgeProvider = bridgeProvider;
    }

    function updateTokenSource(
        bytes32 solToken,
        address srcToken
    ) external onlyOwner {
        CoreStorage storage coreStorage = CoreStorageLib.retreive();

        require(
            address(coreStorage.tokens[solToken].localAddress) != address(0),
            "Bridge Provider Already Added. Use updateTokenBridge"
        );

        coreStorage.tokens[solToken].localAddress = srcToken;
    }

    function setPayloadBridgeProvider(
        IPayloadBridge bridgeProvider
    ) external onlyOwner {
        CoreStorageLib.retreive().plainBridgeProvider = bridgeProvider;
    }

    function setHxroSolanaProgram(bytes32 solanaProgram) external onlyOwner {
        CoreStorageLib.retreive().solanaProgram = solanaProgram;
    }

    function setDataProvider(IDataProvider newDataProvider) external onlyOwner {
        CoreStorageLib.retreive().dataProvider = newDataProvider;
    }
}

