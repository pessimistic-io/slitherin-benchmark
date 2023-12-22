// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Knox Vault Events Interface
 */

interface IVaultEvents {
    /**
     * @notice emitted when the auction contract address is updated
     * @param epoch epoch id
     * @param oldAuction previous auction address
     * @param newAuction new auction address
     * @param caller address of admin
     */
    event AuctionSet(
        uint64 indexed epoch,
        address oldAuction,
        address newAuction,
        address caller
    );

    /**
     * @notice emitted when the is processed
     * @param epoch epoch id
     * @param totalCollateralUsed contracts sold, denominated in the collateral asset
     * @param totalContractsSold contracts sold during the auction
     * @param totalPremiums premiums earned during the auction
     */
    event AuctionProcessed(
        uint64 indexed epoch,
        uint256 totalCollateralUsed,
        uint256 totalContractsSold,
        uint256 totalPremiums
    );

    /**
     * @notice emitted when the auction offset window is updated
     * @param epoch epoch id
     * @param oldStartOffset previous start offset
     * @param newStartOffset new start offset
     * @param oldEndOffset previous end offset
     * @param newEndOffset new end offset
     * @param caller address of admin
     */
    event AuctionWindowOffsetsSet(
        uint64 indexed epoch,
        uint256 oldStartOffset,
        uint256 newStartOffset,
        uint256 oldEndOffset,
        uint256 newEndOffset,
        address caller
    );

    /**
     * @notice emitted when the option delta is updated
     * @param epoch epoch id
     * @param oldDelta previous option delta
     * @param newDelta new option delta
     * @param caller address of admin
     */
    event DeltaSet(
        uint64 indexed epoch,
        int128 oldDelta,
        int128 newDelta,
        address caller
    );

    /**
     * @notice emitted when a distribution is sent to a liquidity provider
     * @param epoch epoch id
     * @param collateralAmount quantity of collateral distributed to the receiver
     * @param shortContracts quantity of short contracts distributed to the receiver
     * @param receiver address of the receiver
     */
    event DistributionSent(
        uint64 indexed epoch,
        uint256 collateralAmount,
        uint256 shortContracts,
        address receiver
    );

    /**
     * @notice emitted when the fee recipient address is updated
     * @param epoch epoch id
     * @param oldFeeRecipient previous fee recipient address
     * @param newFeeRecipient new fee recipient address
     * @param caller address of admin
     */
    event FeeRecipientSet(
        uint64 indexed epoch,
        address oldFeeRecipient,
        address newFeeRecipient,
        address caller
    );

    /**
     * @notice emitted when the keeper address is updated
     * @param epoch epoch id
     * @param oldKeeper previous keeper address
     * @param newKeeper new keeper address
     * @param caller address of admin
     */
    event KeeperSet(
        uint64 indexed epoch,
        address oldKeeper,
        address newKeeper,
        address caller
    );

    /**
     * @notice emitted when an external function reverts
     * @param message error message
     */
    event Log(string message);

    /**
     * @notice emitted when option parameters are set
     * @param epoch epoch id
     * @param expiry expiration timestamp
     * @param strike64x64 strike price as a 64x64 fixed point number
     * @param longTokenId long token id
     * @param shortTokenId short token id
     */
    event OptionParametersSet(
        uint64 indexed epoch,
        uint64 expiry,
        int128 strike64x64,
        uint256 longTokenId,
        uint256 shortTokenId
    );

    /**
     * @notice emitted when the performance fee is collected
     * @param epoch epoch id
     * @param gain amount earned during the epoch
     * @param loss amount lost during the epoch
     * @param feeInCollateral fee from net income, denominated in the collateral asset
     */
    event PerformanceFeeCollected(
        uint64 indexed epoch,
        uint256 gain,
        uint256 loss,
        uint256 feeInCollateral
    );

    /**
     * @notice emitted when the performance fee is updated
     * @param epoch epoch id
     * @param oldPerformanceFee previous performance fee
     * @param newPerformanceFee new performance fee
     * @param caller address of admin
     */
    event PerformanceFeeSet(
        uint64 indexed epoch,
        int128 oldPerformanceFee,
        int128 newPerformanceFee,
        address caller
    );

    /**
     * @notice emitted when the pricer contract address is updated
     * @param epoch epoch id
     * @param oldPricer previous pricer address
     * @param newPricer new pricer address
     * @param caller address of admin
     */
    event PricerSet(
        uint64 indexed epoch,
        address oldPricer,
        address newPricer,
        address caller
    );

    /**
     * @notice emitted when the queue contract address is updated
     * @param epoch epoch id
     * @param oldQueue previous queue address
     * @param newQueue new queue address
     * @param caller address of admin
     */
    event QueueSet(
        uint64 indexed epoch,
        address oldQueue,
        address newQueue,
        address caller
    );

    /**
     * @notice emitted when the reserved liquidity is withdrawn from the pool
     * @param epoch epoch id
     * @param amount quantity of reserved liquidity removed from pool
     */
    event ReservedLiquidityWithdrawn(uint64 indexed epoch, uint256 amount);
}

