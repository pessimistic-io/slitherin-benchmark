// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 *  Sparkblox's `Airdrop` contracts provide a lightweight and easy to use mechanism
 *  to drop tokens.
 *
 *  `AirdropERC721` contract is an airdrop contract for ERC721 tokens. It follows a
 *  push mechanism for transfer of tokens to intended recipients.
 */

interface IAirdropERC721 {
    /// @notice Emitted when an airdrop payment is made to a recipient.
    event AirdropProcessed(address indexed recipient, address NFTAddress, uint256 batchIndex);
    /// @notice Emitted when an airdrop payment is failed to a recipient.
    event AidropFailed(address indexed recipient, address NFTAddress, uint256 batchIndex);
    /// @notice Emitted when an airdrop batch are uploaded to the contract
    event AirdropBatchAdded(AirdropBatch airdropBatch);
    /// @notice Emitted when an airdrop batch is updated
    event AirdropBatchUpdated(AirdropBatch airdropBatch, uint256 batchIndex);
    /// @notice Emitted when an nftAdrees is set
    event NFTAddressAdded(address nftAddress);

    enum AirdropStatus { NOTSTARTED, PROCESSED, FAILED }

    struct AirdropContent {
        address recipient;
        AirdropStatus status;
    }
    /**
     *  @notice struct of airdrop batch.
     *
     *  @param name name of Airdrop Batch.
     *  @param salesPhaseId The id of Sales phase of NFTcontract 
     *  @param amount The total amount to airdrop in this 
     *  @param processedAmount The amount of airdrop processed 
     *  @param failedAmount The amount of airdrop failed 
     *  @param airdropList airdrop
     */
    struct AirdropBatch {
        string name;
        uint256 salesPhaseId;
        uint256 amount;
        uint256 processedAmount;
        uint256 failedAmount;
        AirdropContent[] airdropList;
    }

    function airdrop(uint256 batchIndex) external;
}

