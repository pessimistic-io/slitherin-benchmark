// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {NFT} from "./NFT.sol";
import {SafeTransferLib, ERC20} from "./SafeTransferLib.sol";
import {Auth, Authority} from "./Auth.sol";

contract Marketplace is Auth {
    using SafeTransferLib for ERC20;

    uint256 public feeBps = 500; // 5%
    uint256 public totalOfferCount;

    struct Offer {
        NFT collection;
        uint256 nftId;
        address owner;
        ERC20 quoteToken;
        uint128 askAmount;
        uint32 expirationTime;
        bool canceled;
        bool filled;
    }

    mapping(uint256 => Offer) public offers;

    event AddOffer(
        uint256 indexed offerId,
        address indexed owner,
        address indexed collection,
        uint256 id,
        address quoteToken,
        uint128 askAmount
    );

    event CancelOffer(uint256 indexed offerId);
    event FillOffer(uint256 indexed offerId, address indexed buyer);

    constructor(address _owner, Authority authority) Auth(_owner, authority) {}

    function isValidOffer(uint256 offerId) public view returns (bool) {
        Offer memory offer = offers[offerId];
        NFT collection = offer.collection;
        bool isOwner = collection.ownerOf(offer.nftId) == offer.owner;
        bool isApproved = collection.isApprovedForAll(address(this), offer.owner)
            || collection.getApproved(offer.nftId) == address(this);
        bool isNotExpired = offer.expirationTime > block.timestamp;
        bool isNotCanceled = !offer.canceled;
        bool isNotFilled = !offer.filled;
        return isOwner && isApproved && isNotExpired && isNotCanceled && isNotFilled;
    }

    function createOffer(NFT collection, uint256 nftId, ERC20 quoteToken, uint128 askAmount, uint32 expirationTime)
        external
        returns (uint256 offerId)
    {
        offerId = totalOfferCount++;
        offers[offerId] = Offer(collection, nftId, msg.sender, quoteToken, askAmount, expirationTime, false, false);
        require(isValidOffer(offerId), "Offer is not valid");
    }

    function fillOffer(uint256 offerId) external payable {
        require(isValidOffer(offerId), "Offer is not valid");
        Offer storage offer = offers[offerId];
        uint256 transferFee = offer.collection.getTransferFee(offer.askAmount);
        offer.collection.safeTransferFrom{value: transferFee}(offer.owner, msg.sender, offer.nftId);
        offer.quoteToken.safeTransferFrom(msg.sender, address(this), offer.askAmount);
        uint256 tokenFee = offer.askAmount * feeBps / 10000;
        offer.quoteToken.safeTransfer(offer.owner, offer.askAmount - tokenFee);
        offer.filled = true;
        emit FillOffer(offerId, msg.sender);
    }

    function cancelOffer(uint256 offerId) external {
        Offer storage offer = offers[offerId];
        require(offer.owner == msg.sender, "Only owner can cancel offer");
        offer.canceled = true;
        emit CancelOffer(offerId);
    }

    function withdrawToken(ERC20 token) external requiresAuth {
        token.safeTransfer(msg.sender, token.balanceOf(address(this)));
    }
}

