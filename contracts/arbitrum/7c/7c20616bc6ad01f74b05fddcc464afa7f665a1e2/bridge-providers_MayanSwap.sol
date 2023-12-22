/**
 * Diamond storage
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

struct MayanswapAdapterStorage {
    /**
     * Address of the Mayanswap bridge contract
     */
    address mayanSwap;
    /**
     * Solana address of the Mayanswap program
     */
    bytes32 mayanswap_auction_program;
    /**
     * Constant SOL gas fee to forward (18 decimals)
     */
    uint256 sol_relayer_gas_cost;
    /**
     * Local GAS required for refunds
     */
    uint256 local_refund_gas;
    /**
     * Chain ID of Solana as per the Mayanswap standard
     */
    uint16 solana_chain_id;
    /**
     * Map Solana Token addresses => Mayan ATA
     */
    mapping(bytes32 => bytes32) mayanATAs;
}

library MayanSwapStorageLib {
    // ======================
    //       STORAGE
    // ======================
    // The namespace for the lib (the hash where its stored)
    bytes32 internal constant STORAGE_NAMESPACE =
        keccak256("diamond.hxro.storage.bridge_providers.mayanswap");

    // Function to retreive our storage
    function retreive()
        internal
        pure
        returns (MayanswapAdapterStorage storage s)
    {
        bytes32 position = STORAGE_NAMESPACE;
        assembly {
            s.slot := position
        }
    }

    function mayanswap() internal view returns (address mayanswapBridge) {
        mayanswapBridge = retreive().mayanSwap;
    }

    function mayanAuctionProgram()
        internal
        view
        returns (bytes32 mayanSolAuctionProgram)
    {
        mayanSolAuctionProgram = retreive().mayanswap_auction_program;
    }

    function solSwapFee() internal view returns (uint256 solConstantFee) {
        solConstantFee = retreive().sol_relayer_gas_cost;
    }

    function localRefundGas() internal view returns (uint256 localConstantFee) {
        localConstantFee = retreive().local_refund_gas;
    }

    function solanaChainId() internal view returns (uint16 solChainId) {
        solChainId = retreive().solana_chain_id;
    }

    function getMayanAssociatedTokenAccount(
        bytes32 solToken
    ) internal view returns (bytes32 ata) {
        ata = retreive().mayanATAs[solToken];
    }
}

