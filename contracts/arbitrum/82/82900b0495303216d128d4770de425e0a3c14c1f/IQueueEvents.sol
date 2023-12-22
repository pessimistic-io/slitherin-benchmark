// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Knox Queue Events Interface
 */

interface IQueueEvents {
    /**
     * @notice emitted when a deposit is cancelled
     * @param epoch epoch id
     * @param depositer address of depositer
     * @param amount quantity of collateral assets removed from queue
     */
    event Cancel(uint64 indexed epoch, address depositer, uint256 amount);

    /**
     * @notice emitted when a deposit is made
     * @param epoch epoch id
     * @param depositer address of depositer
     * @param amount quantity of collateral assets added to queue
     */
    event Deposit(uint64 indexed epoch, address depositer, uint256 amount);

    /**
     * @notice emitted when the exchange helper contract address is updated
     * @param oldExchangeHelper previous exchange helper address
     * @param newExchangeHelper new exchange helper address
     * @param caller address of admin
     */
    event ExchangeHelperSet(
        address oldExchangeHelper,
        address newExchangeHelper,
        address caller
    );

    /**
     * @notice emitted when the max TVL is updated
     * @param epoch epoch id
     * @param oldMaxTVL previous max TVL amount
     * @param newMaxTVL new max TVL amount
     * @param caller address of admin
     */
    event MaxTVLSet(
        uint64 indexed epoch,
        uint256 oldMaxTVL,
        uint256 newMaxTVL,
        address caller
    );

    /**
     * @notice emitted when vault shares are redeemed
     * @param epoch epoch id
     * @param receiver address of receiver
     * @param depositer address of depositer
     * @param shares quantity of vault shares sent to receiver
     */
    event Redeem(
        uint64 indexed epoch,
        address receiver,
        address depositer,
        uint256 shares
    );

    /**
     * @notice emitted when the queued deposits are processed
     * @param epoch epoch id
     * @param deposits quantity of collateral assets processed
     * @param pricePerShare vault price per share calculated
     * @param shares quantity of vault shares sent to queue contract
     * @param claimTokenSupply quantity of claim tokens in supply
     */
    event ProcessQueuedDeposits(
        uint64 indexed epoch,
        uint256 deposits,
        uint256 pricePerShare,
        uint256 shares,
        uint256 claimTokenSupply
    );
}

