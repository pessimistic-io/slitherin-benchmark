// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.6;

interface ITheHoursAuctionHouse {
    struct Auction {
        // ID for the Hour (ERC721 token ID)
        uint256 hourId;
        // The current highest bid amount
        uint256 amount;
        // The time that the auction started
        uint256 startTime;
        // The time that the auction is scheduled to end
        uint256 endTime;
        // The address of the current highest bid
        address payable bidder;
        // Whether or not the auction has been settled
        bool settled;
        // The mint details for the highest bidder
        bytes32 mintDetails;
    }

    event AuctionCreated(
        uint256 indexed hourId,
        uint256 startTime,
        uint256 endTime
    );

    event AuctionBid(
        uint256 indexed hourId,
        address sender,
        uint256 value,
        bool extended,
        bytes32 mintDetails
    );

    event AuctionExtended(uint256 indexed hourId, uint256 endTime);

    event AuctionSettled(
        uint256 indexed hourId,
        address winner,
        uint256 amount,
        bytes32 mintDetails
    );

    event AuctionTimeBufferUpdated(uint256 timeBuffer);

    event AuctionReservePriceUpdated(uint256 reservePrice);

    event AuctionMinBidIncrementPercentageUpdated(
        uint256 minBidIncrementPercentage
    );

    function settleAuction() external;

    function settleCurrentAndCreateNewAuction() external;

    function createBid(
        uint256 JacksonId,
        bytes32 mintDetails,
        bool shouldCheckAllowlist,
        bytes32[] calldata proof
    ) external payable;

    function pause() external;

    function unpause() external;
}

