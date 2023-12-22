// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./VaultStorage.sol";

/**
 * @title Knox Vault Admin Interface
 */

interface IVaultAdmin {
    /************************************************
     *  ADMIN
     ***********************************************/

    /**
     * @notice sets the new auction
     * @dev the auction contract address must be set during the vault initialization
     * @param newAuction address of the new auction
     */
    function setAuction(address newAuction) external;

    /**
     * @notice sets the start and end offsets for the auction
     * @param newStartOffset new start offset
     * @param newEndOffset new end offset
     */
    function setAuctionWindowOffsets(
        uint256 newStartOffset,
        uint256 newEndOffset
    ) external;

    /**
     * @notice sets the option delta value
     * @param newDelta64x64 new option delta value as a 64x64 fixed point number
     */
    function setDelta64x64(int128 newDelta64x64) external;

    /**
     * @notice sets the new fee recipient
     * @param newFeeRecipient address of the new fee recipient
     */
    function setFeeRecipient(address newFeeRecipient) external;

    /**
     * @notice sets the new keeper
     * @param newKeeper address of the new keeper
     */
    function setKeeper(address newKeeper) external;

    /**
     * @notice sets the new pricer
     * @dev the pricer contract address must be set during the vault initialization
     * @param newPricer address of the new pricer
     */
    function setPricer(address newPricer) external;

    /**
     * @notice sets the new queue
     * @dev the queue contract address must be set during the vault initialization
     * @param newQueue address of the new queue
     */
    function setQueue(address newQueue) external;

    /**
     * @notice sets the performance fee for the vault
     * @param newPerformanceFee64x64 performance fee as a 64x64 fixed point number
     */
    function setPerformanceFee64x64(int128 newPerformanceFee64x64) external;

    /************************************************
     *  INITIALIZE AUCTION
     ***********************************************/

    /**
     * @notice sets the option parameters which will be sold, then initializes the auction
     */
    function initializeAuction() external;

    /************************************************
     *  INITIALIZE EPOCH
     ***********************************************/

    /**
     * @notice collects performance fee from epoch income, processes the queued deposits,
     * increments the epoch id, then sets the auction prices
     * @dev it assumed that an auction has already been initialized
     */
    function initializeEpoch() external;

    /************************************************
     *  PROCESS AUCTION
     ***********************************************/

    /**
     * @notice processes the auction when it has been finalized or cancelled
     * @dev it assumed that an auction has already been initialized and the auction prices
     * have been set
     */
    function processAuction() external;
}

