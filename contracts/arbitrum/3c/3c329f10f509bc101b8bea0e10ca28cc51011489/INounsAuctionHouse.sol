// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

interface INounsAuctionHouse {
    struct Auction {
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
        // Auction type: for character and weapon
        uint16 auctionType;
    }

    event AuctionCreated(uint256 indexed auctionId, uint256 startTime, uint256 endTime);

    event AuctionBid(uint256 indexed auctionId, address sender, uint256 value, bool extended);

    event AuctionExtended(uint256 indexed auctionId, uint256 endTime);

    event AuctionSettled(uint256 indexed auctionId, address winner, uint256 amount);

    event AuctionTimeBufferUpdated(uint256 timeBuffer);

    event AuctionReservePriceUpdated(uint256 reservePrice);

    event AuctionMinBidIncrementPercentageUpdated(uint256 minBidIncrementPercentage);

    function settleAuction(uint256 _auctionId) external;

    function createAuction(uint16 _auctionType) external;

    // function settleCurrentAndCreateNewAuction(uint256 _auctionId, uint16 _auctionType) external;

    function createBid(uint256 auctionId) external payable;

    function pause() external;

    function unpause() external;

    function setTimeBuffer(uint256 timeBuffer) external;

    function setReservePrice(uint256 reservePrice) external;

    function setMinBidIncrementPercentage(uint8 minBidIncrementPercentage) external;
}

