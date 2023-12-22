// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AuctionStorage.sol";

/**
 * @title Knox Auction Events Interface
 */

interface IAuctionEvents {
    /**
     * @notice emitted when the auction max/min prices have been set
     * @param epoch epoch id
     * @param strike64x64 strike price as a 64x64 fixed point number
     * @param offsetStrike64x64 offset strike price as a 64x64 fixed point number
     * @param spot64x64 spot price as a 64x64 fixed point number
     * @param maxPrice64x64 max price as a 64x64 fixed point number
     * @param minPrice64x64 min price as a 64x64 fixed point number
     */
    event AuctionPricesSet(
        uint64 indexed epoch,
        int128 strike64x64,
        int128 offsetStrike64x64,
        int128 spot64x64,
        int128 maxPrice64x64,
        int128 minPrice64x64
    );

    /**
     * @notice emitted when the exchange auction status is updated
     * @param epoch epoch id
     * @param status auction status
     */
    event AuctionStatusSet(uint64 indexed epoch, AuctionStorage.Status status);

    /**
     * @notice emitted when the delta offset is updated
     * @param oldDeltaOffset previous delta offset
     * @param newDeltaOffset new delta offset
     * @param caller address of admin
     */
    event DeltaOffsetSet(
        int128 oldDeltaOffset,
        int128 newDeltaOffset,
        address caller
    );

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
     * @notice emitted when an external function reverts
     * @param message error message
     */
    event Log(string message);

    /**
     * @notice emitted when the minimum order size is updated
     * @param oldMinSize previous minimum order size
     * @param newMinSize new minimum order size
     * @param caller address of admin
     */
    event MinSizeSet(uint256 oldMinSize, uint256 newMinSize, address caller);

    /**
     * @notice emitted when a market or limit order has been placed
     * @param epoch epoch id
     * @param orderId order id
     * @param buyer address of buyer
     * @param price64x64 price paid as a 64x64 fixed point number
     * @param size quantity of options purchased
     * @param isLimitOrder true if order is a limit order
     */
    event OrderAdded(
        uint64 indexed epoch,
        uint128 orderId,
        address buyer,
        int128 price64x64,
        uint256 size,
        bool isLimitOrder
    );

    /**
     * @notice emitted when a limit order has been cancelled
     * @param epoch epoch id
     * @param orderId order id
     * @param buyer address of buyer
     */
    event OrderCanceled(uint64 indexed epoch, uint128 orderId, address buyer);

    /**
     * @notice emitted when an order (filled or unfilled) is withdrawn
     * @param epoch epoch id
     * @param buyer address of buyer
     * @param refund amount sent back to the buyer as a result of an overpayment
     * @param fill amount in long token contracts sent to the buyer
     */
    event OrderWithdrawn(
        uint64 indexed epoch,
        address buyer,
        uint256 refund,
        uint256 fill
    );

    /**
     * @notice emitted when the pricer contract address is updated
     * @param oldPricer previous pricer address
     * @param newPricer new pricer address
     * @param caller address of admin
     */
    event PricerSet(address oldPricer, address newPricer, address caller);
}

