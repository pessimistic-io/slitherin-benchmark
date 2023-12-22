// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

library Errors {
    string public constant INVALID_LENGTH= "invalid length";
    string public constant INVALID_FEE = "invalid platform fee";
    string public constant INVALID_TREASURY_ADDRESS = "invalid _treasury address";
    string public constant EMPTY_NFTS = "empty nftList";
    string public constant NOT_CHRONOS_NFT = "not chronos nft";
    string public constant SELLER_NOT_OWNER_OF_NFT = "caller is not token owner or approved";
    string public constant INVALID_TOKEN = "not allowed payment token";
    string public constant INVALID_ITEM_ID = "invalid item id";
    string public constant NOT_SALE_PERIOD = "not sale period";
    string public constant INVALID_TOKEN_AMOUNT = "invalid nativeToken amount";
    string public constant ALREADY_SOLD = "already sold";
    string public constant LOW_BID_PRICE = "low bid price";
    string public constant NOT_EXISTED_SAILID = "not exists sailId";
    string public constant NO_PERMISSION = "has no permission";
    string public constant INVALID_TOKEN_ID = "unavailable token id";
    string public constant INVALID_SALE_DURATION = "saleDuration should be bigger than 0";
    string public constant INVALID_PRICE = "invalid price";
    string public constant INVALID_BUYER = "buyer can't be same as seller";
    string public constant NOT_EXISTED_AUCTIONID = "unavailable auctionId";
    string public constant BEFORE_AUCTION_MATURITY = "before auction maturity";
    string public constant NOT_EXISTED_OFFERID = "unavailable offerId";
    string public constant NOT_ENOUGH_ALLOWANCE = "not enough allowance";
}
