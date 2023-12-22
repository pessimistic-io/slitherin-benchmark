// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./IERC20.sol";
import "./IERC721.sol";

contract MoetaNFTAuctions is Ownable {
    struct Auction {
        address nftAddress;
        uint256 tokenId;
        uint256 startingTime;
        uint256 endingTime;
    }

    struct Bid {
        address bidder;
        uint256 amount;
    }

    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => Bid) public bids;
    uint256 public nextAuctionId;

    IERC20 public moetaToken =
        IERC20(0x6D630F3946E3BBBf49e22c6Fd53185D35b3F1045);

    constructor() {}

    function newAuction(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _startingTime,
        uint256 _duration
    ) public onlyOwner {
        auctions[nextAuctionId] = Auction(
            _nftAddress,
            _tokenId,
            _startingTime,
            _startingTime + _duration
        );
        nextAuctionId++;
        IERC721(_nftAddress).transferFrom(msg.sender, address(this), _tokenId);
    }

    function cancelAuction(uint256 _auctionId) public onlyOwner {
        Auction memory auction = auctions[_auctionId];
        require(auction.endingTime > block.timestamp, "Auction already ended");
        IERC721(auction.nftAddress).transferFrom(
            address(this),
            msg.sender,
            auction.tokenId
        );
        delete auctions[_auctionId];
    }

    function bid(uint256 _auctionId, uint256 _amount) public {
        require(_auctionId < nextAuctionId, "Auction does not exist");
        Auction memory auction = auctions[_auctionId];
        require(
            auction.startingTime <= block.timestamp,
            "Auction not started yet"
        );
        require(auction.endingTime > block.timestamp, "Auction already ended");
        require(_amount > bids[_auctionId].amount, "Bid too low");
        require(
            moetaToken.transferFrom(msg.sender, address(this), _amount),
            "Transfer failed"
        );
        if (bids[_auctionId].amount > 0) {
            require(
                moetaToken.transfer(
                    bids[_auctionId].bidder,
                    bids[_auctionId].amount
                ),
                "Transfer failed"
            );
        }
        bids[_auctionId] = Bid(msg.sender, _amount);
    }

    function settleAuction(uint256 _auctionId) public {
        require(_auctionId < nextAuctionId, "Auction does not exist");
        Auction memory auction = auctions[_auctionId];
        require(auction.endingTime <= block.timestamp, "Auction not ended yet");
        require(bids[_auctionId].amount > 0, "No bids");
        require(
            moetaToken.transfer(address(0xdead), bids[_auctionId].amount),
            "Burn failed"
        );

        IERC721(auction.nftAddress).transferFrom(
            address(this),
            bids[_auctionId].bidder,
            auction.tokenId
        );
        delete bids[_auctionId];
    }

    function isAuctionLive(uint256 _auctionId) public view returns (bool) {
        Auction memory auction = auctions[_auctionId];
        return
            auction.startingTime <= block.timestamp &&
            auction.endingTime > block.timestamp;
    }

    function latestAuctionId() public view returns (uint256) {
        if (nextAuctionId > 0) {
            return nextAuctionId - 1;
        } else {
            return 0;
        }
    }
}

