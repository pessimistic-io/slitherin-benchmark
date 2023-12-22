// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./SelectNFT.sol";
import "./Ownable.sol";

struct ListingData {
    address owner;
    address reserve;
    uint256 price;
}

struct AuctionData {
    address owner;
    address highestBidder;
    uint256 highestBid;
    uint256 reservePrice;
    uint256 endTime;
}

struct OfferData {
    uint256 offerAmount;
}

interface WrappedEth {
    function withdraw(uint256 amt) external;
    function balanceOf(address src) external returns(uint256);
    function transferFrom(address src, address dst, uint wad) external;
    function allowance(address src, address op) external returns(uint);
}

contract SelectNFTMarket is Ownable {
    uint256 public constant MINIMUM_BID_INCREMENT = 0.01 ether;

    mapping(uint256 => ListingData) public listings;
    mapping(uint256 => AuctionData) public auctions;
    mapping(uint256 => mapping(address => OfferData)) public offers;

    SelectNFT private selectNFT;
    WrappedEth public weth = WrappedEth(0xEBbc3452Cc911591e4F18f3b36727Df45d6bd1f9);

    event ListingCreated(uint256 indexed tokenId, address indexed owner, address reservedFor, uint256 price);
    event ListingCancelled(uint256 indexed tokenId, address indexed owner);
    event ListingPurchased(uint256 indexed tokenId, address indexed previousOwner, address indexed newOwner, uint256 price);

    event OfferCreated(uint256 indexed tokenId, address indexed from, uint256 price);
    event OfferRevoked(uint256 indexed tokenId, address indexed from);

    event AuctionCreated(uint256 indexed tokenId, address indexed owner, uint256 reservePrice);
    event AuctionBidReceived(uint256 indexed tokenId, address indexed from, uint256 bid);
    event AuctionSettled(uint256 indexed tokenId, address indexed settler, address indexed winner, uint256 bid);

    receive() external payable {}

    function setSelectNFT(SelectNFT nft) public onlyOwner {
        selectNFT = nft; 
    }

    function setWeth(WrappedEth _weth) public onlyOwner {
        weth = _weth;
    }

    function createListing(uint256 tokenId, uint256 price) public {
        address tokenOwner = selectNFT.ownerOf(tokenId);
        require(msg.sender == tokenOwner, "SelectNFTMarket: not authorized to create listing for token");
        listings[tokenId] = ListingData(tokenOwner, address(0), price);
        emit ListingCreated(tokenId, tokenOwner, address(0), price);
    }

    function createReservedlisting(uint256 tokenId, uint256 price, address reserve) public {
        address tokenOwner = selectNFT.ownerOf(tokenId);
        require(msg.sender == tokenOwner, "SelectNFTMarket: not authorized to create listing for token");
        listings[tokenId] = ListingData(msg.sender, reserve, price);
        emit ListingCreated(tokenId, msg.sender, address(0), price);
    }

    function cancelListing(uint256 tokenId) public {
        address tokenOwner = selectNFT.ownerOf(tokenId);
        require(msg.sender == tokenOwner, "SelectNFTMarket: not authorized to create listing for token");
        delete listings[tokenId];
        emit ListingCancelled(tokenId, msg.sender);
    }

    function buy(uint256 tokenId) public payable {
        address tokenOwner = listings[tokenId].owner;
        uint256 listingPrice = listings[tokenId].price;
        require(tokenOwner != address(0), "SelectNFTMarket: token not listed or does not exist");
        require(listings[tokenId].reserve == address(0) || listings[tokenId].reserve == msg.sender, "SelectNFTMarket: token not reserved for you");
        require(msg.value == listingPrice, "SelectNFTMarket: invalid value for listing");

        delete listings[tokenId];
        
        uint256 sellerPayout = listingPrice;
        (address[] memory feeReceivers, uint16[] memory feeBasisPoints) = selectNFT.getProjectFees(selectNFT.projectIdFromTokenId(tokenId));
        for (uint256 i = 0; i < feeReceivers.length; i++) {
            uint256 payout = listingPrice * feeBasisPoints[i] / 10000;
            sellerPayout -= payout;
            (bool success,) = feeReceivers[i].call{value: payout}("");
            require(success, "SelectShop: transfer to beneficiary failed");
        }

        if (sellerPayout > 0) {
            (bool payoutSuccess,) = tokenOwner.call{ value: sellerPayout }("");
            require(payoutSuccess, "SelectNFTMarket: seller payout failed");
        }

        selectNFT.transferFrom(tokenOwner, msg.sender, tokenId);
        
        emit ListingPurchased(tokenId, tokenOwner, msg.sender, listingPrice);
    }

    function buyFor(uint256 tokenId, address to) public payable {
        address tokenOwner = listings[tokenId].owner;
        uint256 listingPrice = listings[tokenId].price;
        require(tokenOwner != address(0), "SelectNFTMarket: token not listed or does not exist");
        require(listings[tokenId].reserve == address(0) || listings[tokenId].reserve == to, "SelectNFTMarket: token not reserved for recipient");
        require(msg.value == listingPrice, "SelectNFTMarket: invalid value for listing");

        delete listings[tokenId];

        uint256 sellerPayout = listingPrice;
        (address[] memory feeReceivers, uint16[] memory feeBasisPoints) = selectNFT.getProjectFees(selectNFT.projectIdFromTokenId(tokenId));
        for (uint256 i = 0; i < feeReceivers.length; i++) {
            uint256 payout = listingPrice * feeBasisPoints[i] / 10000;
            sellerPayout -= payout;
            (bool success,) = feeReceivers[i].call{value: payout}("");
            require(success, "SelectShop: transfer to beneficiary failed");
        }

        if (sellerPayout > 0) {
            (bool payoutSuccess,) = tokenOwner.call{ value: sellerPayout }("");
            require(payoutSuccess, "SelectNFTMarket: seller payout failed");
        }

        selectNFT.transferFrom(tokenOwner, to, tokenId);

        emit ListingPurchased(tokenId, tokenOwner, to, listingPrice);
    }

    function adminBuy(uint256 tokenId, address to) public onlyOwner {
        address tokenOwner = listings[tokenId].owner;
        require(tokenOwner != address(0), "SelectNFTMarket: token not listed or does not exist");
        require(listings[tokenId].reserve == address(0) || listings[tokenId].reserve == to, "SelectNFTMarket: token not reserved for recipient");

        uint256 price = listings[tokenId].price;
        delete listings[tokenId];

        selectNFT.transferFrom(tokenOwner, to, tokenId);

        emit ListingPurchased(tokenId, tokenOwner, to, price);
    }

    function offer(uint256 tokenId, uint256 price) public {
        require(weth.balanceOf(msg.sender) >= price, "SelectNFTMarket: balance not enough for offer");
        require(weth.allowance(msg.sender, address(this)) >= price, "SelectNFTMarket: allowance not enough for offer");
        offers[tokenId][msg.sender].offerAmount = price;
        emit OfferCreated(tokenId, msg.sender, price);
    }

    function revokeOffer(uint256 tokenId) public {
        delete offers[tokenId][msg.sender];
        emit OfferRevoked(tokenId, msg.sender);
    }

    function acceptOffer(uint256 tokenId, address from) public {
        address tokenOwner = selectNFT.ownerOf(tokenId);
        uint256 offerAmount = offers[tokenId][from].offerAmount;
        require(msg.sender == tokenOwner, "SelectNFTMarket: only the token owner can accept an offer");
        require(offerAmount > 0, "SelectNFTMarket: no offer for token from that address");

        delete offers[tokenId][from];

        weth.transferFrom(from, address(this), offerAmount);
        weth.withdraw(offerAmount);
        
        uint256 sellerPayout = offerAmount;
        (address[] memory feeReceivers, uint16[] memory feeBasisPoints) = selectNFT.getProjectFees(selectNFT.projectIdFromTokenId(tokenId));
        for (uint256 i = 0; i < feeReceivers.length; i++) {
            uint256 payout = offerAmount * feeBasisPoints[i] / 10000;
            sellerPayout -= payout;
            (bool success,) = feeReceivers[i].call{value: payout}("");
            require(success, "SelectShop: transfer to beneficiary failed");
        }

        if (sellerPayout > 0) {
            (bool payoutSuccess,) = tokenOwner.call{ value: sellerPayout }("");
            require(payoutSuccess, "SelectNFTMarket: seller payout failed");
        }

        selectNFT.transferFrom(tokenOwner, from, tokenId);
    }

    function createAuction(uint256 tokenId, uint256 reservePrice, uint256 endTime) public {
        address tokenOwner = selectNFT.ownerOf(tokenId);
        require(msg.sender == tokenOwner, "SelectNFTMarket: not authorized to create auction for token");
        require(block.timestamp < endTime, "SelectNFTMarket: endTime must be in the future");
        auctions[tokenId] = AuctionData(msg.sender, address(0), 0, reservePrice, endTime);
        emit AuctionCreated(tokenId, msg.sender, reservePrice);
    }

    function bid(uint256 tokenId) public payable {
        require(auctions[tokenId].owner != address(0), "SelectNFTMarket: token not up for auction or does not exist");
        require(msg.value >= auctions[tokenId].reservePrice, "SelectNFTMarket: bid does not meet or exceed reserve price");
        require(msg.value > auctions[tokenId].highestBid + MINIMUM_BID_INCREMENT, "SelectNFTMarket: must bid more than previous bidder");
        require(block.timestamp <= auctions[tokenId].endTime, "SelectNFTMarket: auction closed");

        auctions[tokenId].highestBidder.call{ value: auctions[tokenId].highestBid }("");

        auctions[tokenId].highestBidder = msg.sender;
        auctions[tokenId].highestBid = msg.value;

        if (auctions[tokenId].endTime - block.timestamp < 15 minutes) {
            auctions[tokenId].endTime = block.timestamp + 15 minutes;
        }

        emit AuctionBidReceived(tokenId, msg.sender, msg.value);
    }

    function settle(uint256 tokenId) public {
        address tokenOwner = auctions[tokenId].owner;
        address highestBidder = auctions[tokenId].highestBidder;
        require(tokenOwner != address(0), "SelectNFTMarket: token not up for auction or does not exist");
        require(highestBidder != address(0), "SelectNFTMarket: no bids were made for this auction");
        require(block.timestamp > auctions[tokenId].endTime, "SelectNFTMarket: auction not closed");

        uint256 highestBid = auctions[tokenId].highestBid;

        delete auctions[tokenId];

        uint256 sellerPayout = highestBid;
        (address[] memory feeReceivers, uint16[] memory feeBasisPoints) = selectNFT.getProjectFees(selectNFT.projectIdFromTokenId(tokenId));
        for (uint256 i = 0; i < feeReceivers.length; i++) {
            uint256 payout = highestBid * feeBasisPoints[i] / 10000;
            sellerPayout -= payout;
            (bool success,) = feeReceivers[i].call{value: payout}("");
            require(success, "SelectShop: transfer to beneficiary failed");
        }

        if (sellerPayout > 0) {
            (bool payoutSuccess,) = tokenOwner.call{ value: sellerPayout }("");
            require(payoutSuccess, "SelectNFTMarket: seller payout failed");
        }

        selectNFT.transferFrom(tokenOwner, highestBidder, tokenId);
        emit AuctionSettled(tokenId, msg.sender, highestBidder, highestBid);
    }
}

