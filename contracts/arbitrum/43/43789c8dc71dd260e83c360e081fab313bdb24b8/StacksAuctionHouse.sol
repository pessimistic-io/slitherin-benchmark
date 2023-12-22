// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "./Ownable.sol";

contract StacksAuctionHouse is Ownable {
  mapping(uint => Auction) public auctions;
  mapping(address => uint[]) public userAuctionsWon;

  uint public createdAuctions = 0;
  address payable public treasuryAddress;
  bool public auctionOpened = true;
  uint startTimeOfFirstAuction = 1677628800; // Wed Mar 01 2023 00:00:00 GMT+0000

  struct Auction {
    uint endPrice;
    address payable topBidder;
    uint startTime;
    uint endTime;
    bool closed;
  }

  constructor(address payable _treasuryAddress) {
    treasuryAddress = _treasuryAddress;
    // Create the first auction
    auctions[0] = Auction({
      endPrice: 0,
      topBidder: payable(address(0)),
      startTime: startTimeOfFirstAuction,
      endTime: (startTimeOfFirstAuction + 1 days) - 1,
      closed: false
    });
    createdAuctions++;
    // Create next 30 auctions
    createAuctions(30);
  }

  function getUserAuctionsWon(address _user) public view returns (uint[] memory) {
    return userAuctionsWon[_user];
  }

  function getCurrentWinner() public view returns (address payable) {
    return auctions[daysSinceStart()].topBidder;
  }

  function getAuctionWinner(uint _tokenId) public view returns (address payable) {
    return auctions[_tokenId].topBidder;
  }

  function getCurrentAuction() public view returns (Auction memory) {
    return auctions[daysSinceStart()];
  }

  function getLastCreatedAuction() public view returns (Auction memory) {
    return auctions[createdAuctions - 1];
  }

  function getAuction(uint _tokenId) public view returns (Auction memory) {
    return auctions[_tokenId];
  }

  function bid() public payable {
    require(auctionOpened, "Auction is closed");
    Auction memory auction = getCurrentAuction();
    uint auctionId = daysSinceStart();
    uint paidVal = msg.value;

    require(paidVal > auction.endPrice, "Bid is too low");
    uint lastBid = auction.endPrice;
    address payable lastBidder = auction.topBidder;
    // update the auction
    auctions[auctionId].topBidder = payable(msg.sender);
    auctions[auctionId].endPrice = paidVal;
    userAuctionsWon[msg.sender].push(auctionId);

    if(lastBidder != address(0)){
      // refund last bidder
      userAuctionsWon[lastBidder].pop();
      lastBidder.transfer(lastBid);
    }

    Auction memory lastAuction = getAuction(auctionId - 1);
    if(!lastAuction.closed) {
      _closeAuction(auctionId - 1);
    }
  }

  function closeAuction(uint _tokenId) public onlyOwner {
    Auction memory auction = auctions[_tokenId];
    require(auction.endTime < block.timestamp, "Auction is still open");
    require(!auction.closed, "Auction already closed");
    _closeAuction(_tokenId);
  }

  function _closeAuction(uint _tokenId) private {
    Auction memory auction = auctions[_tokenId];
    // close the auction
    auctions[_tokenId].closed = true;
    // move funds to the treasury
    treasuryAddress.transfer(auction.endPrice);
  }

  // Admin functions
  function setTreasuryAddress(address payable _treasuryAddress) public onlyOwner {
    treasuryAddress = _treasuryAddress;
  }

  function setAuctionOpened(bool _open) public onlyOwner {
    auctionOpened = _open;
  }

  // run to create auctions in bulk for the next _amount days
  function createAuctions(uint _amount) public onlyOwner {
    uint finalCreatedAuctions = createdAuctions + _amount;
    for (uint i = createdAuctions; i < finalCreatedAuctions; i++) {
      createNextAuction();
    }
  }

  function createNextAuction() private {
    Auction memory lastAuction = auctions[createdAuctions - 1];
    auctions[createdAuctions] = Auction({
      endPrice: 0,
      topBidder: payable(address(0)),
      startTime: lastAuction.endTime + 1, // 1 second after the last auction ends
      endTime: lastAuction.endTime + 1 days, // 1 day after the last auction ends
      closed: false
    });
    createdAuctions++;
  }

  // daysSinceStart() same as currentAuctionId()
  function daysSinceStart() public view returns (uint) {
    return (block.timestamp - startTimeOfFirstAuction) / 1 days;
  }
}

