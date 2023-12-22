// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface ITreasureMarketplace {
    struct Listing {
        uint256 quantity;
        uint256 pricePerItem;
        uint256 expirationTime;
    }

    function listings(
        address _nftAddress,
        uint256 _tokenId,
        address _seller
    ) external view returns (Listing memory);

    function createListing(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _quantity,
        uint256 _pricePerItem,
        uint256 _expirationTime
    ) external;

    function updateListing(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _newQuantity,
        uint256 _newPricePerItem,
        uint256 _newExpirationTime
    ) external;

    function cancelListing(address _nftAddress, uint256 _tokenId) external;

    /// @notice Buy a listed item. You must authorize this marketplace with your payment token to completed the buy.
    /// @param  _nftAddress      which token contract holds the offered token
    /// @param  _tokenId         the identifier for the token to be bought
    /// @param  _owner           current owner of the item(s) to be bought
    /// @param  _quantity        how many of this token identifier to be bought (or 1 for a ERC-721 token)
    /// @param  _maxPricePerItem the maximum price (in units of the paymentToken) for each token offered
    function buyItem(
        address _nftAddress,
        uint256 _tokenId,
        address _owner,
        uint64 _quantity,
        uint128 _maxPricePerItem
    ) external;

    function addToWhitelist(address _nft) external;

    function removeFromWhitelist(address _nft) external;
}

