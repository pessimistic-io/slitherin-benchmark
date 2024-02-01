// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./ERC165Checker.sol";
import "./EnumerableSet.sol";

import "./IMarketplaceCore.sol";
import "./IMarketplaceSellerRegistry.sol";

import "./MarketplaceLib.sol";
import "./SettlementLib.sol";
import "./BidTreeLib.sol";

abstract contract MarketplaceCore is IMarketplaceCore {
    using EnumerableSet for EnumerableSet.AddressSet;
    using BidTreeLib for BidTreeLib.BidTree;

    bool private _enabled;
    address private _approvedListers;
     
    uint40 private _listingCounter;
    mapping (uint40 => MarketplaceLib.Listing) private _listings;
    mapping (uint40 => BidTreeLib.BidTree) private _listingBidTree;
    mapping (uint40 => address[]) private _listingBidTreeFinalOrder;
    mapping (address => mapping (address => uint256)) private _escrow;

    // Marketplace fee
    uint16 public feeBPS;
    uint16 public referrerBPS;
    mapping (address => uint256) _feesCollected;

    uint256[50] private __gap;

    /**
     * @dev Set enabled
     */
    function _setEnabled(bool enabled) internal {
        _enabled = enabled;
        emit MarketplaceEnabled(msg.sender, enabled);
    }

    /**
     * @dev Set marketplace fees
     */
    function _setFees(uint16 feeBPS_, uint16 referrerBPS_) internal {
        require(feeBPS_ <= 1500 && referrerBPS_ <= 1500, "Invalid fee config");
        feeBPS = feeBPS_;
        referrerBPS = referrerBPS_;
        emit MarketplaceFees(msg.sender, feeBPS, referrerBPS);
    }

    /**
     * @dev Withdraw accumulated fees from marketplace
     */
    function _withdraw(address erc20, uint256 amount, address payable receiver) internal {
        require(_feesCollected[erc20] >= amount, "Invalid amount");
        _feesCollected[erc20] -= amount;
        SettlementLib.sendTokens(erc20, address(this), receiver, amount);
        emit MarketplaceWithdraw(msg.sender, erc20, amount, receiver);
    }

    /**
     * @dev Withdraw escrow amounts
     */
    function _withdrawEscrow(address erc20, uint256 amount) internal {
        require(_escrow[msg.sender][erc20] >= amount, "Invalid amount");
        _escrow[msg.sender][erc20] -= amount;
        SettlementLib.sendTokens(erc20, address(this), payable(msg.sender), amount);
        emit MarketplaceWithdrawEscrow(msg.sender, erc20, amount);
    }

    /**
     * Create a listing
     */
    function _createListing(address payable seller, MarketplaceLib.ListingDetails calldata listingDetails, MarketplaceLib.TokenDetails calldata tokenDetails, MarketplaceLib.ListingReceiver[] calldata listingReceivers, bool enableReferrer) internal returns (uint40) {
        require(_enabled, "Disabled");

        _listingCounter++;
        MarketplaceLib.Listing storage listing = _listings[_listingCounter];
        listing.marketplaceBPS = feeBPS;
        if (enableReferrer) {
            listing.referrerBPS = referrerBPS;
        }
        listing.seller = seller;
        MarketplaceLib.constructListing(_listingCounter, listing, listingDetails, tokenDetails, listingReceivers);

        return _listingCounter;
    }

    /**
     * Modify an active listing
     */
    function _modifyListing(uint40 listingId, uint256 initialAmount, uint48 startTime, uint48 endTime) internal {
        require(listingId <= _listingCounter, "Listing not found");
        MarketplaceLib.Listing storage listing = _listings[listingId];
        MarketplaceLib.modifyListing(listingId, listing, initialAmount, startTime, endTime);
    }

    /**
     * Mark a listing as complete (meaning the buyer can finalize)
     */
    function _completeListing(uint40 listingId, MarketplaceLib.DeliveryFees calldata fees) internal {
        require(listingId > 0 && listingId <= _listingCounter, "Listing not found");
        MarketplaceLib.Listing storage listing = _listings[listingId];
        MarketplaceLib.completeListing(listingId, listing, fees);
        if (fees.deliverDeciBPS == 0) {
            // Automatically finalize listing if fees are 0
            finalize(listingId);
        }
    }

    /**
     * @dev See {IMarketplaceCore-purchase}.
     */
    function purchase(uint40 listingId) external payable virtual override {
        _purchase(payable(address(0)), listingId, 1, "");
    }
    function purchase(uint40 listingId, bytes calldata data) external payable virtual override {
        _purchase(payable(address(0)), listingId, 1, data);
    }
    
    /**
     * @dev See {IMarketplaceCore-purchase}.
     */
    function purchase(address referrer, uint40 listingId) external payable virtual override {
        _purchase(payable(referrer), listingId, 1, "");
    }
    function purchase(address referrer, uint40 listingId, bytes calldata data) external payable virtual override {
        _purchase(payable(referrer), listingId, 1, data);
    }

    /**
     * @dev See {IMarketplaceCore-purchase}.
     */  
    function purchase(uint40 listingId, uint24 count) external payable virtual override {
        _purchase(payable(address(0)), listingId, count, "");
    }
    function purchase(uint40 listingId, uint24 count, bytes calldata data) external payable virtual override {
        _purchase(payable(address(0)), listingId, count, data);
    }
  
    /**
     * @dev See {IMarketplaceCore-purchase}.
     */
    function purchase(address referrer, uint40 listingId, uint24 count) external payable virtual override {
        _purchase(payable(referrer), listingId, count, "");
    }
    function purchase(address referrer, uint40 listingId, uint24 count, bytes calldata data) external payable virtual override {
        _purchase(payable(referrer), listingId, count, data);
    }
    
    function _purchase(address payable referrer, uint40 listingId, uint24 count, bytes memory data) private {
        require(listingId > 0 && listingId <= _listingCounter, "Listing not found");
        MarketplaceLib.Listing storage listing = _listings[listingId];
        require(!MarketplaceLib.isAuction(listing.details.type_), "Not available to purchase");

        SettlementLib.performPurchase(referrer, listingId, listing, count, _feesCollected, data);
    }


    /**
     * @dev See {IMarketplaceCore-bid}.
     */
    function bid(uint40 listingId, bool increase) external payable virtual override {
        _bid(msg.value, payable(address(0)), listingId, increase, "");
    }
    function bid(uint40 listingId, bool increase, bytes calldata data) external payable virtual override {
        _bid(msg.value, payable(address(0)), listingId, increase, data);
    }

    /**
     * @dev See {IMarketplaceCore-bid}.
     */
    function bid(address payable referrer, uint40 listingId, bool increase) external payable virtual override {
        _bid(msg.value, referrer, listingId, increase, "");
    }
    function bid(address payable referrer, uint40 listingId, bool increase, bytes calldata data) external payable virtual override {
        _bid(msg.value, referrer, listingId, increase, data);
    }

    /**
     * @dev See {IMarketplaceCore-bid}.
     */
    function bid(uint40 listingId, uint256 bidAmount, bool increase) external virtual override {
        _bid(bidAmount, payable(address(0)), listingId, increase, "");
    }
    function bid(uint40 listingId, uint256 bidAmount, bool increase, bytes calldata data) external virtual override {
        _bid(bidAmount, payable(address(0)), listingId, increase, data);
    }

    /**
     * @dev See {IMarketplaceCore-bid}.
     */
    function bid(address payable referrer, uint40 listingId, uint256 bidAmount, bool increase) external virtual override {
        _bid(bidAmount, referrer, listingId, increase, "");
    }
    function bid(address payable referrer, uint40 listingId, uint256 bidAmount, bool increase, bytes calldata data) external virtual override {
        _bid(bidAmount, referrer, listingId, increase, data);
    }

    function _bid(uint256 bidAmount, address payable referrer, uint40 listingId, bool increase, bytes memory data) private {
        require(listingId > 0 && listingId <= _listingCounter, "Listing not found");
        MarketplaceLib.Listing storage listing = _listings[listingId];
        MarketplaceLib.ListingType listingType = listing.details.type_;

        if (listingType == MarketplaceLib.ListingType.INDIVIDUAL_AUCTION) {
             SettlementLib.performBidIndividual(listingId, listing, bidAmount, referrer, increase, _escrow, data);
        } else if (listingType == MarketplaceLib.ListingType.RANKED_AUCTION) {
            BidTreeLib.BidTree storage bidTree = _listingBidTree[listingId];
            SettlementLib.performBidRanked(listingId, listing, bidTree, bidAmount, increase, _escrow, data);
        } else {
            revert("Listing not found");
        }
    }

    /**
     * @dev See {IMarketplaceCore-collect}.
     */
    function collect(uint40 listingId) external virtual override {
        require(listingId > 0 && listingId <= _listingCounter, "Listing not found");
        MarketplaceLib.Listing storage listing = _listings[listingId];
        require((listing.flags & MarketplaceLib.FLAG_MASK_FINALIZED) == 0, "Listing not found");
        require(listing.details.startTime != 0 && listing.details.endTime < block.timestamp, "Listing still active");
        require(msg.sender == listing.seller, "Only seller can collect");

        // Only tokens in custody and individual auction types allow funds collection pre-delivery
        require(!listing.token.lazy && listing.details.type_ == MarketplaceLib.ListingType.INDIVIDUAL_AUCTION, "Cannot collect");
        
        MarketplaceLib.Bid storage bid_ = listing.bid;
        require(!bid_.settled, "Already collected");
        
        // Settle bid
        SettlementLib.settleBid(bid_, listing, _feesCollected);
    }

    /**
     * Cancel an active sale and refund outstanding amounts
     */
    function _cancelListing(uint40 listingId, uint16 holdbackBPS) internal virtual {
        require(listingId > 0 && listingId <= _listingCounter, "Listing not found");
        MarketplaceLib.Listing storage listing = _listings[listingId];
        require((listing.flags & MarketplaceLib.FLAG_MASK_FINALIZED) == 0, "Listing not found");
        require(holdbackBPS <= 1000, "Invalid input");

        // Immediately end and finalize
        if (listing.details.startTime == 0) listing.details.startTime = uint48(block.timestamp);
        listing.details.endTime = uint48(block.timestamp);
        listing.flags |= MarketplaceLib.FLAG_MASK_FINALIZED;

        // Refund open bids
        if ((listing.flags & MarketplaceLib.FLAG_MASK_HAS_BID) != 0) {
            if (listing.details.type_ == MarketplaceLib.ListingType.INDIVIDUAL_AUCTION) {
                SettlementLib.refundBid(listing.bid, listing, holdbackBPS, _escrow);
            } else if (listing.details.type_ == MarketplaceLib.ListingType.RANKED_AUCTION) {
                BidTreeLib.BidTree storage bidTree = _listingBidTree[listingId];
                address bidder = bidTree.first();
                while (bidder != address(0)) {
                    BidTreeLib.Bid storage bid_ = bidTree.getBid(bidder);
                    SettlementLib.refundBid(payable(bidder), bid_, listing, holdbackBPS, _escrow);
                    bidder = bidTree.next(bidder);
                }
            }
        }

        if (!listing.token.lazy) {
            // Return remaining items to seller
            SettlementLib.deliverToken(listing, listing.seller, 1, 0, true);
        }
        emit MarketplaceLib.CancelListing(listingId, msg.sender, holdbackBPS);
    }

    /**
     * @dev See {IMarketplaceCore-finalize}.
     */
    function finalize(uint40 listingId) public payable virtual override {
        require(listingId > 0 && listingId <= _listingCounter, "Listing not found");
        MarketplaceLib.Listing storage listing = _listings[listingId];
        require((listing.flags & MarketplaceLib.FLAG_MASK_FINALIZED) == 0, "Listing not found");
        require(listing.details.startTime != 0 && listing.details.endTime < block.timestamp, "Listing still active");
        require((listing.flags & MarketplaceLib.FLAG_MASK_HAS_BID) == 0 || 
            (listing.flags & MarketplaceLib.FLAG_MASK_COMPLETABLE) != 0, "Christie's verification needed");

        // Mark as finalized first to prevent re-entrancy
        listing.flags |= MarketplaceLib.FLAG_MASK_FINALIZED;

        if ((listing.flags & MarketplaceLib.FLAG_MASK_HAS_BID) == 0) {
            if (!listing.token.lazy) {
                // No buyer, return to seller
                SettlementLib.deliverToken(listing, listing.seller, 1, 0, true);
            }
        } else if (listing.details.type_ == MarketplaceLib.ListingType.INDIVIDUAL_AUCTION) {
            listing.totalSold += listing.details.totalPerSale;
            MarketplaceLib.Bid storage currentBid = listing.bid;
            if (listing.token.lazy) {
                SettlementLib.deliverTokenLazy(listingId, listing, currentBid.bidder, 1, currentBid.amount, 0);
            } else {
                SettlementLib.deliverToken(listing, currentBid.bidder, 1, currentBid.amount, false);
            }
            
            // Settle bid
            SettlementLib.settleBid(currentBid, listing, _feesCollected);
            // Mark delivered
            currentBid.delivered = true;

        } else if (listing.details.type_ == MarketplaceLib.ListingType.RANKED_AUCTION) {
            // Final sort order
            BidTreeLib.BidTree storage bidTree = _listingBidTree[listingId];
            address[] storage bidTreeFinalOrder = _listingBidTreeFinalOrder[listingId];
            address key = bidTree.first();
            while (key != address(0)) {
                bidTreeFinalOrder.push(key);
                key = bidTree.next(key);
            }
           listing.totalSold += uint24(bidTreeFinalOrder.length*listing.details.totalPerSale);
        } else {
            // Invalid type
            revert("Invalid type");
        }

        emit MarketplaceLib.FinalizeListing(listingId);
    }

    /**
     * @dev See {IMarketplace-deliver}.
     */
    function deliver(uint40 listingId, uint256 bidIndex) external payable override {
        require(listingId > 0 && listingId <= _listingCounter, "Listing not found");
        MarketplaceLib.Listing storage listing = _listings[listingId];
        require((listing.flags & MarketplaceLib.FLAG_MASK_FINALIZED) != 0, "Listing not found");
        require(listing.token.lazy && listing.details.type_ == MarketplaceLib.ListingType.RANKED_AUCTION, "Invalid listing type to deliver items");

        BidTreeLib.BidTree storage bidTree = _listingBidTree[listingId];

        require(bidIndex < bidTree.size, "Bid index out of range");
        address key = bidTree.first();
        uint256 keyIndex = 0;
        while (keyIndex < bidIndex) {
            key = bidTree.next(key);
            keyIndex++;
        }
        BidTreeLib.Bid storage bid_ = bidTree.getBid(key);
        require(!bid_.refunded, "Bid has been refunded");
        require(!bid_.delivered, "Bid already delivered");

        // Mark delivered first to prevent re-entrancy
        bid_.delivered = true;

        // Deliver item
        uint256 refundAmount = SettlementLib.deliverTokenLazy(listingId, listing, key, 1, bid_.amount, bidIndex);
        require(refundAmount < bid_.amount, "Invalid delivery return value");

        // Refund bidder if necessary
        if (refundAmount > 0) {
            SettlementLib.refundTokens(listing.details.erc20, payable(key), refundAmount, _escrow);
        }
        // Settle bid
        SettlementLib.settleBid(bid_, listing, refundAmount, _feesCollected);
        
    }

    /**
     * @dev See {IMarketplaceCore-getListing}.
     */
    function getListing(uint40 listingId) external view override returns(Listing memory listing) {
        require(listingId > 0 && listingId <= _listingCounter, "Invalid listing");
        MarketplaceLib.Listing storage internalListing = _listings[listingId];
        listing.id = listingId;
        listing.seller = internalListing.seller;
        listing.finalized = (internalListing.flags & MarketplaceLib.FLAG_MASK_FINALIZED) != 0;
        listing.completable = (internalListing.flags & MarketplaceLib.FLAG_MASK_COMPLETABLE) != 0;
        listing.totalSold = internalListing.totalSold;
        listing.marketplaceBPS = internalListing.marketplaceBPS;
        listing.referrerBPS = internalListing.referrerBPS;
        listing.details = internalListing.details;
        listing.token = internalListing.token;
        listing.receivers = internalListing.receivers;
        listing.fees = internalListing.fees;
        if ((internalListing.flags & MarketplaceLib.FLAG_MASK_HAS_BID) != 0) {
          listing.bid = internalListing.bid;
        }
    }

    /**
     * @dev See {IMarketplaceCore-getListingCurrentPrice}.
     */
    function getListingCurrentPrice(uint40 listingId) external view override returns(uint256) {
        require(listingId > 0 && listingId <= _listingCounter, "Invalid listing");
        MarketplaceLib.Listing storage listing = _listings[listingId];
        require(listing.details.endTime > block.timestamp || listing.details.startTime == 0 || (listing.flags & MarketplaceLib.FLAG_MASK_FINALIZED) != 0, "Listing is expired");
        return SettlementLib.computeListingPrice(listing, _listingBidTree[listingId]);
    }

    /**
     * @dev See {IMarketplaceCore-getListingTotalPrice}.
     */
    function getListingTotalPrice(uint40 listingId, uint24 count) external view override returns(uint256) {
        require(listingId > 0 && listingId <= _listingCounter, "Invalid listing");
        MarketplaceLib.Listing storage listing = _listings[listingId];
        require(listing.details.endTime > block.timestamp || listing.details.startTime == 0 || (listing.flags & MarketplaceLib.FLAG_MASK_FINALIZED) != 0, "Listing is expired");
        require(listing.details.totalAvailable > 1 && count*listing.details.totalPerSale <= (listing.details.totalAvailable-listing.totalSold), "Invalid count");
        return SettlementLib.computeTotalPrice(listing, count, false);
    }

    /**
     * @dev See {IMarketplaceCore-geListingDeliverFee}.
     */
    function getListingDeliverFee(uint40 listingId, uint256 price) external view override returns(uint256) {
        require(listingId > 0 && listingId <= _listingCounter, "Invalid listing");
        MarketplaceLib.Listing storage listing = _listings[listingId];
        return SettlementLib.computeDeliverFee(listing, price);
    }

    /**
     * @dev See {IMarketplaceCore-getBids}.
     */
    function getBids(uint40 listingId) external view virtual override returns(MarketplaceLib.Bid[] memory bids) {
        require(listingId > 0 && listingId <= _listingCounter, "Invalid listing");
        MarketplaceLib.Listing storage listing = _listings[listingId];
        if ((listing.flags & MarketplaceLib.FLAG_MASK_HAS_BID) != 0) {
            if (listing.details.type_ == MarketplaceLib.ListingType.RANKED_AUCTION) {
                BidTreeLib.BidTree storage bidTree = _listingBidTree[listingId];
                if ((listing.flags & MarketplaceLib.FLAG_MASK_FINALIZED) == 0) {
                    bids = new MarketplaceLib.Bid[](bidTree.size);
                    uint256 index = 0;
                    address key = bidTree.first();
                    while (key != address(0)) {
                        BidTreeLib.Bid storage bid_ = bidTree.getBid(key);
                        bids[index] = MarketplaceLib.Bid({amount:bid_.amount, bidder:payable(key), delivered:bid_.delivered, settled:bid_.settled, refunded:bid_.refunded, timestamp:bid_.timestamp, referrer:payable(address(0))});
                        key = bidTree.next(key);
                        index++;
                    }
                } else {
                    address[] storage bidTreeFinalOrder = _listingBidTreeFinalOrder[listingId];
                    bids = new MarketplaceLib.Bid[](bidTreeFinalOrder.length);
                    for (uint i = 0; i < bidTreeFinalOrder.length; i++) {
                        address key = bidTreeFinalOrder[i];
                        BidTreeLib.Bid storage bid_ = bidTree.getBid(key);
                        bids[i] = MarketplaceLib.Bid({amount:bid_.amount, bidder:payable(key), delivered:bid_.delivered, settled:bid_.settled, refunded:bid_.refunded, timestamp:bid_.timestamp, referrer:payable(address(0))});
                    }
                }
            } else {
                bids = new MarketplaceLib.Bid[](1);
                bids[0] = listing.bid;
            }
        }
        return bids;
    }

    /**
     * @dev Implement to support receiving of tokens (needed for token ingestion to create a listing)
     */
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external virtual returns(bytes4) {
        return this.onERC1155Received.selector;
    }

}
