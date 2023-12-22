// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./ICollectionData.sol";

interface ILoot8Marketplace is ICollectionData {

    enum ListingType {
        ALL,
        PUBLIC,
        PRIVATE
    }

    event MarketPlaceFeeSet(uint256 _mintFee, uint256 _saleFee);
    event ItemListedForSale(
        uint256 _listingId, 
        address _collection, 
        uint256 _tokenId, 
        address _paymentToken, 
        uint256 _price, 
        ListingType _listingType
    );
    event ItemDelisted(uint256 _listingId, address _collection, uint256 _tokenId);
    event ItemSold(address _collection, uint256 _tokenId);
    event AddedPaymentToken(address _token);
    event RemovedPaymentToken(address _token);

    struct Listing {
        uint256 id;
        address seller;
        address passport;
        address collection;
        uint256 tokenId;
        address paymentToken;
        uint256 price;
        uint256 sellerShare;
        address payable[] royaltyRecipients;
        uint256[] amounts;
        uint256 marketplaceFees;
        ListingType listingType;
        
        // Storage gap
        uint256[10] __gap;
    }

    function setMarketPlaceFees(uint256 _mintFee, uint256 _saleFee) external;
    function listingExists(address _collection, uint256 _tokenId, ListingType _listingType) external view returns(bool _exists, uint256 _listingId);
    function checkItemValidity(address _passport, address _collection) external returns(bool);
    function checkTraderEligibility(address _patron, address _passport, address _collection, ListingType _listingType) external view returns(bool);
    function listCollectible(
        address _passport,
        address _collection, 
        uint256 _tokenId,
        address _paymentToken, 
        uint256 _price, 
        bytes memory _signature,
        uint256 _expiry,
        ListingType _listingType
    ) external returns(uint256 _listingId);
    function delistCollectible(uint256 _listingId) external;
    function buy(uint256 _listingId, bytes memory _signature, uint256 _expiry) external;
    function getAllListingsForCollection(address _collection) external view returns(Listing[] memory _listings);
    function addPaymentToken(address _token) external;
    function removePaymentToken(address _token) external;
    function getListingById(uint256 _listingId) external view returns(Listing memory _listing);
}
