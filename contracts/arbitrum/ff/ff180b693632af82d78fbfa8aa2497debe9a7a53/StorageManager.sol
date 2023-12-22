// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./src_MayanSwap.sol";
import "./Core.sol";
import "./AccessControl.sol";
import {MayanSwap} from "./src_MayanSwap.sol";
import "./IBridgeProvider.sol";

struct MayanData {
    address mayanswapBridge;
    bytes32 mayanSolAuctionProgram;
    uint256 solConstantFee;
    uint256 refundFee;
    uint16 solChainId;
    bytes32 ata;
}

contract MayanStorageManagerFacet is AccessControlled {
    // ==============
    //     ERRORS
    // ==============
    error TokenExistsUseUpdateMethods();

    // ==============
    //    SETTERS
    // ==============
    /**
     * Add HXRO token through Mayanswap bridge,
     * classifies usual info + mayan related info
     * **@notice If classifying a token that's meant to go through Mayan, use this method!!**
     * @param localToken - Local address of the token
     * @param solToken - Address of the token on Solana
     * @param mayanswapBridgeProvider - Address of the mayanswap adapter
     * @param mayanATA - Associated Token Account of Mayanswap "Main" program to the token
     */
    function addMayanToken(
        address localToken,
        bytes32 solToken,
        ITokenBridge mayanswapBridgeProvider,
        bytes32 mayanATA
    ) external onlyOwner {
        CoreStorage storage coreStorage = CoreStorageLib.retreive();
        if (MayanSwapStorageLib.retreive().mayanATAs[solToken] != bytes32(0))
            revert TokenExistsUseUpdateMethods();

        // Set ATA
        MayanSwapStorageLib.retreive().mayanATAs[solToken] = mayanATA;

        Token memory existingToken = coreStorage.tokens[solToken];

        if (
            existingToken.localAddress != address(0) ||
            address(existingToken.bridgeProvider) != address(0)
        ) revert TokenExistsUseUpdateMethods();

        // Set core storage
        coreStorage.tokens[solToken] = Token({
            solAddress: solToken,
            localAddress: localToken,
            bridgeProvider: mayanswapBridgeProvider
        });
        coreStorage.allSupportedTokens.push(solToken);
    }

    /**
     * Set Associated Token Account of a SOL token
     * @param solToken  - Sol Token to classify on
     * @param ata  - Mayanswap "Main" program ATA of that token
     */
    function setATA(bytes32 solToken, bytes32 ata) external onlyOwner {
        MayanSwapStorageLib.retreive().mayanATAs[solToken] = ata;
    }

    /**
     * Set the MayanSwap swap-bridge contract address
     * @param newBridgeContract - Address of the new bridge Contract
     */
    function setMayanBridgeContract(
        address newBridgeContract
    ) external onlyOwner {
        MayanSwapStorageLib.retreive().mayanSwap = newBridgeContract;
    }

    /**
     * Set the Mayanswap auction program address (Solana)
     * @param newAuctionProgram - The new auction program address
     */
    function setMayanAuctionProgram(
        bytes32 newAuctionProgram
    ) external onlyOwner {
        MayanSwapStorageLib
            .retreive()
            .mayanswap_auction_program = newAuctionProgram;
    }

    /**
     * Set the SOL fee that's taken in RelayerFees in Mayanswap (Meant to be converted to ETH when transacting)
     * @param newConstantSolFee - The new constant swap fee denominated in SOL, 18 decimals
     */
    function setSolSwapFee(uint256 newConstantSolFee) external onlyOwner {
        MayanSwapStorageLib.retreive().sol_relayer_gas_cost = newConstantSolFee;
    }

    /**
     * Set the refund fee to use when sending Mayanswap swaps
     * @param newConstantGasRefundFee - The new constant local refund gas fee (WEI)
     */
    function setLocalRefundFee(
        uint256 newConstantGasRefundFee
    ) external onlyOwner {
        MayanSwapStorageLib
            .retreive()
            .local_refund_gas = newConstantGasRefundFee;
    }

    /**
     * Set the chain ID used to identify Solana in Mayanswap
     * Unlikely that it should be used.
     * @param newChainId - The new chain ID of solana
     */
    function setSolanaChainId(uint16 newChainId) external onlyOwner {
        MayanSwapStorageLib.retreive().solana_chain_id = newChainId;
    }

    // ==============
    //    GETTERS
    // ==============
    function getData(
        bytes32 solToken
    ) external view returns (MayanData memory mayanData) {
        address mayanswapBridge = MayanSwapStorageLib.mayanswap();
        bytes32 mayanSolAuctionProgram = MayanSwapStorageLib
            .mayanAuctionProgram();

        uint256 solConstantFee = MayanSwapStorageLib.solSwapFee();

        uint256 refundFee = MayanSwapStorageLib.localRefundGas() * tx.gasprice;

        uint16 solChainId = MayanSwapStorageLib.solanaChainId();

        bytes32 ata = MayanSwapStorageLib.getMayanAssociatedTokenAccount(
            solToken
        );

        mayanData = MayanData(
            mayanswapBridge,
            mayanSolAuctionProgram,
            solConstantFee,
            refundFee,
            solChainId,
            ata
        );
    }

    function mayanswap() external view returns (MayanSwap mayanswapBridge) {
        mayanswapBridge = MayanSwap(payable(MayanSwapStorageLib.mayanswap()));
    }

    function mayanAuctionProgram()
        external
        view
        returns (bytes32 mayanSolAuctionProgram)
    {
        mayanSolAuctionProgram = MayanSwapStorageLib.mayanAuctionProgram();
    }

    function solSwapFee() external view returns (uint256 solConstantFee) {
        solConstantFee = MayanSwapStorageLib.solSwapFee();
    }

    function localRefundFee() external view returns (uint256 refundFee) {
        refundFee = MayanSwapStorageLib.localRefundGas() * tx.gasprice;
    }

    function solanaChainId() external view returns (uint16 solChainId) {
        solChainId = MayanSwapStorageLib.solanaChainId();
    }

    function getMayanAssociatedTokenAccount(
        bytes32 solToken
    ) external view returns (bytes32 ata) {
        ata = MayanSwapStorageLib.getMayanAssociatedTokenAccount(solToken);
    }
}

