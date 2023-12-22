// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {Ownable} from "./Ownable.sol";
import {MerkleProof} from "./MerkleProof.sol";

contract BucketModule is Ownable {
    uint256 public minimumContribution = 0.1 ether;
    bool public auctionActive;

    struct BidInfo {
        uint256 contribution; // cumulative sum of ETH bids
        uint32 tokensClaimed; // tracker for claimed tokens
        bool refundClaimed; // has user been refunded yet
    }

    mapping(address => BidInfo) public userData;
    uint256 public price;

    modifier whenAuctionActive() {
        require(auctionActive, "Auction is not active");
        _;
    }

    event Bid(address bidder, uint256 bidAmount, uint256 bidderTotal, uint256 bucketTotal);

    modifier whenAuctionNotActive() {
        require(!auctionActive, "Auction is still active");
        _;
    }

    constructor() {
    }

    function bid() external payable whenAuctionActive {
        BidInfo storage bidder = userData[msg.sender]; // get user's current bid total
        uint256 contribution_ = bidder.contribution;
        unchecked { // does not overflow
            contribution_ += msg.value;
        }
        require(contribution_ >= minimumContribution, "Lower than min bid amount");
        bidder.contribution = uint256(contribution_);
        emit Bid(msg.sender, msg.value, contribution_, address(this).balance);
    }

    function refundAmount(address a) public view returns (uint256) {
        return userData[a].contribution % price;
    }

    function amountPurchased(address a) public view returns (uint256) {
        return userData[a].contribution / price;
    }

    function _amountPurchased(uint256 _contribution, uint256 _price) 
        internal
        pure
        returns (uint256)
    {
        return _contribution / _price;
    }
    
    function _isLoser(address _userAddress) internal view returns(bool) {
        BidInfo memory userBidInfo = userData[_userAddress];
        return userBidInfo.contribution < price;
    }

    function _refundAmount(uint256 _contribution, uint256 _price) 
        internal
        pure
        returns (uint256)
    {
        return _contribution % _price;
    }

    function setMinimumContribution(uint256 minimumContributionInWei_) external onlyOwner {
        minimumContribution = minimumContributionInWei_;
    }

    function setClearingPrice(uint256 priceInWei_) external onlyOwner whenAuctionNotActive {
        price = priceInWei_;
    }

    function setAuctionActive(bool active_) external onlyOwner {
        require(price == 0, "Price has been set");
        auctionActive = active_;
    }
}
