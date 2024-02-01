// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IERC721MarketplaceInternal} from "./IERC721MarketplaceInternal.sol";
import {ScapesMarketplaceStorage} from "./ScapesMarketplaceStorage.sol";
import {ERC721BaseInternal} from "./ERC721BaseInternal.sol";

/// @title ERC721MarketplaceInternal
/// @author akuti.eth, jalil.eth | scapes.eth
/// @dev The internal logic of the ERC721Marketplace.
abstract contract ERC721MarketplaceInternal is
    IERC721MarketplaceInternal,
    ERC721BaseInternal
{
    /// @dev Make a new offer. Emits an {OfferCreated} event.
    function _makeOffer(
        uint256 tokenId,
        uint80 price,
        address to
    ) internal {
        if (price == 0) revert ERC721Marketplace__InvalidPrice();
        if (!_isApprovedOrOwner(msg.sender, tokenId))
            revert ERC721Base__NotOwnerOrApproved();
        ScapesMarketplaceStorage.Offer storage offer = ScapesMarketplaceStorage
            .layout()
            .offers[tokenId];

        offer.price = price;
        offer.specificBuyer = to;

        emit OfferCreated(tokenId, price, to);
    }

    /// @dev Revoke an active offer. Emits an {OfferWithdrawn} event.
    function _cancelOffer(uint256 tokenId) internal {
        ScapesMarketplaceStorage.Offer storage offer = ScapesMarketplaceStorage
            .layout()
            .offers[tokenId];
        if (offer.price == 0) revert ERC721Marketplace__NonExistentOffer();
        offer.price = 0;
        offer.specificBuyer = address(0);
        emit OfferWithdrawn(tokenId);
    }
}

