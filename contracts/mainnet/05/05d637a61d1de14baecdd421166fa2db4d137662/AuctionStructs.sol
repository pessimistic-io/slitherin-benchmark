// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

enum AuctionStatus {
    NONE,
    ACTIVE,
    SETTLED,
    CANCELLED
}

enum AuctionType {
    ABSOLUTE,
    EXTENDED
}

struct Asset {
    address tokenAddress;
    uint256 tokenId;
    uint256 qty;
}

struct Auction {
    uint256 id;
    uint256 startingPrice;
    uint256 reservePrice;
    uint256 minBidThreshold;
    address seller;
    uint256 startDate;
    uint256 endDate;
    uint256 topBid;
    address topBidder;
    AuctionStatus status;
    AuctionType auctionType;
}

