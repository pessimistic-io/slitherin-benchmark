// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {ERC721MarketplaceInternal} from "./ERC721MarketplaceInternal.sol";
import {ScapesMarketplaceStorage} from "./ScapesMarketplaceStorage.sol";
import {ERC721BaseInternal} from "./ERC721BaseInternal.sol";
import {ScapesERC721MetadataStorage} from "./ScapesERC721MetadataStorage.sol";
import {IChild} from "./IChild.sol";

/// @title ERC721Marketplace
/// @author akuti.eth, jalil.eth | scapes.eth
/// @notice Adds a marketplace to ERC721 tokens that only takes royalties when tokens are sold at a gain.
/// @dev A diamond facet that adds marketplace functionality to ERC721 tokens.
contract ERC721Marketplace is ERC721BaseInternal, ERC721MarketplaceInternal {
    uint256 internal constant INITIAL_LAST_PRICE = 0.1 ether;

    /// @notice Get an exisiting current offer.
    function getOffer(uint256 tokenId)
        external
        view
        returns (ScapesMarketplaceStorage.Offer memory offer)
    {
        ScapesMarketplaceStorage.Layout storage d = ScapesMarketplaceStorage
            .layout();
        offer = d.offers[tokenId];
        if (offer.price == 0) revert ERC721Marketplace__NonExistentOffer();
    }

    /// @notice List your token publicly.
    /// @dev Make an offer. Emits an {OfferCreated} event. An existing offer is replaced.
    function makeOffer(uint256 tokenId, uint80 price) external {
        // max price is 1_208_925 ETH
        _makeOffer(tokenId, price, address(0));
    }

    /// @notice List multiple tokens publicly.
    /// @dev Batch make offers. Emits an {OfferCreated} event for each offer. Existing offers are replaced.
    function batchMakeOffer(
        uint256[] calldata tokenIds,
        uint80[] calldata prices
    ) external {
        if (tokenIds.length != prices.length)
            revert ERC721Marketplace__InvalidArguments();
        uint256 length = tokenIds.length;
        for (uint256 i = 0; i < length; ) {
            _makeOffer(tokenIds[i], prices[i], address(0));
            unchecked {
                i++;
            }
        }
    }

    /// @notice List your token privately for one address.
    /// @dev Make a private offer. Emits an {OfferCreated} event. An existing offer is replaced.
    function makeOfferTo(
        uint256 tokenId,
        uint80 price,
        address to
    ) external {
        _makeOffer(tokenId, price, to);
    }

    /// @notice List multiple tokens privately for given addresses.
    /// @dev Batch make private offers. Emits an {OfferCreated} event for each offer. Existing offers are replaced.
    function batchMakeOfferTo(
        uint256[] calldata tokenIds,
        uint80[] calldata prices,
        address[] calldata tos
    ) external {
        if (tokenIds.length != prices.length || tokenIds.length != tos.length)
            revert ERC721Marketplace__InvalidArguments();
        uint256 length = tokenIds.length;
        for (uint256 i = 0; i < length; ) {
            _makeOffer(tokenIds[i], prices[i], tos[i]);
            unchecked {
                i++;
            }
        }
    }

    /// @notice Cancel an existing offer.
    /// @dev Allow approved operators to cancel an offer. Emits an {OfferWithdrawn} event.
    function cancelOffer(uint256 tokenId) public {
        if (!_isApprovedOrOwner(msg.sender, tokenId))
            revert ERC721Base__NotOwnerOrApproved();
        _cancelOffer(tokenId);
    }

    /// @notice Cancel multiple existing offers.
    /// @dev Allow approved operators to cancel existing offers. Emits an {OfferWithdrawn} event for each offer.
    function batchCancelOffer(uint256[] calldata tokenIds) external {
        uint256 length = tokenIds.length;
        for (uint256 i = 0; i < length; ) {
            cancelOffer(tokenIds[i]);
            unchecked {
                i++;
            }
        }
    }

    /// @notice Buy an offered item.
    /// @dev Buy an item that is offered publicly or to the sender. Emits a {Sale} event.
    function buy(uint256 tokenId) external payable {
        ScapesMarketplaceStorage.Offer memory offer = ScapesMarketplaceStorage
            .layout()
            .offers[tokenId];
        if (offer.price > 0 && msg.value != offer.price)
            revert ERC721Marketplace__InvalidValue();
        _buy(tokenId, offer);
    }

    /// @notice Buy multiple offered items.
    /// @dev Batch buy items that are offered publicly or to the sender. Emits a {Sale} event for each sale.
    function batchBuy(uint256[] calldata tokenIds) external payable {
        ScapesMarketplaceStorage.Layout storage d = ScapesMarketplaceStorage
            .layout();
        uint256 totalCost;
        uint256 length = tokenIds.length;
        for (uint256 i = 0; i < length; ) {
            ScapesMarketplaceStorage.Offer memory offer = d.offers[tokenIds[i]];
            totalCost += offer.price;
            if (msg.value < totalCost) revert ERC721Marketplace__InvalidValue();
            _buy(tokenIds[i], offer);
            unchecked {
                i++;
            }
        }
        if (msg.value > totalCost) revert ERC721Marketplace__InvalidValue();
    }

    /// @dev Logic of the buy function, check that item is offered, sent value
    ///      is correct and caluclate correct fee to apply
    function _buy(uint256 tokenId, ScapesMarketplaceStorage.Offer memory offer)
        internal
    {
        uint256 price = offer.price;
        uint256 lastPrice = (offer.lastPrice == 0)
            ? INITIAL_LAST_PRICE
            : offer.lastPrice;
        if (price == 0) revert ERC721Marketplace__NonExistentOffer();
        // If it is a private sale, make sure the buyer is the private sale recipient.
        if (
            offer.specificBuyer != address(0) &&
            offer.specificBuyer != msg.sender
        ) {
            revert ERC721Marketplace__NonExistentOffer();
        }
        if (msg.value < offer.price) revert ERC721Marketplace__InvalidValue();
        ScapesMarketplaceStorage.Layout storage d = ScapesMarketplaceStorage
            .layout();

        // Keep track of the last price of the token.
        d.offers[tokenId].lastPrice = offer.price;

        // Close Offer
        d.offers[tokenId].price = 0;
        if (offer.specificBuyer != address(0))
            d.offers[tokenId].specificBuyer = address(0);

        // Seller gets msg value - fees set as BPS.
        address seller = _ownerOf(tokenId);
        if (lastPrice < offer.price) {
            uint256 fullFeePrice = (10_000 * lastPrice) / (10_000 - d.bps);
            uint256 fee = price < fullFeePrice
                ? price - lastPrice
                : (price * d.bps) / 10_000;
            _transferEtherAndCheck(seller, price - fee);
            _transferEtherAndCheck(d.beneficiary, fee);
        } else {
            _transferEtherAndCheck(seller, msg.value);
        }

        _safeTransfer(seller, msg.sender, tokenId, "");
        emit Sale(tokenId, seller, msg.sender, price);
    }

    function _transferEtherAndCheck(address receiver, uint256 value) internal {
        (bool sent, ) = payable(receiver).call{gas: 3_000, value: value}("");
        if (!sent) revert ERC721Marketplace__PaymentFailed();
    }

    /**
     * @inheritdoc ERC721BaseInternal
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721BaseInternal) {
        IChild(ScapesERC721MetadataStorage.layout().scapeBound).update(
            from,
            to,
            tokenId
        );
        super._afterTokenTransfer(from, to, tokenId);
    }
}

