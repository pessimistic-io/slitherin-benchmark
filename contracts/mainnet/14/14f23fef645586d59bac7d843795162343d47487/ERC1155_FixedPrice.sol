pragma solidity 0.8.12;

import {ExchangeCore} from "./ExchangeCore.sol";
import {IERC1155} from "./IERC1155.sol";
import {IWETH} from "./IWETH.sol";

abstract contract ERC1155FixedPrice is ExchangeCore {
    struct FixedPriceListingERC1155 {
        uint256 quantity;
        uint256 price;
    }

    struct OfferERC1155 {
        uint256 value;
        uint128 quantity;
        uint128 expiresAt;
    }

    mapping(address => mapping(uint256 => mapping(address => FixedPriceListingERC1155)))
        public fixedPriceListingsERC1155;

    mapping(address => mapping(uint256 => mapping(address => OfferERC1155)))
        public offersERC1155;

    event ItemListedERC1155(
        address indexed account,
        address indexed collection,
        uint256 tokenId,
        uint256 price,
        uint256 quantity
    );

    event ItemUpdatedERC1155(
        address indexed account,
        address indexed collection,
        uint256 tokenId,
        uint256 price,
        uint256 quantity
    );

    event PriceChangedERC1155(
        address indexed account,
        address indexed collection,
        uint256 tokenId,
        uint256 price,
        uint256 quantity
    );

    event ItemRemovedERC1155(
        address indexed account,
        address indexed collection,
        uint256 tokenId
    );

    event ItemPurchasedERC1155(
        address indexed buyer,
        address seller,
        address indexed collection,
        uint256 tokenId,
        uint256 quantity,
        uint256 price
    );

    event OfferMadeERC1155(
        address account,
        address indexed collection,
        uint256 tokenId,
        uint256 quantity,
        uint256 offerValue,
        uint256 validityDuration,
        uint256 expiresAt
    );

    event OfferUpdatedERC1155(
        address account,
        address indexed collection,
        uint256 tokenId,
        uint256 quantity,
        uint256 offerValue,
        uint256 validityDuration,
        uint256 expiresAt
    );

    event OfferCancelledERC1155(
        address account,
        address indexed collection,
        uint256 tokenId
    );

    event OfferAcceptedERC1155(
        address beneficiary,
        address seller,
        address indexed collection,
        uint256 tokenId,
        uint128 quantity,
        uint256 price
    );

    function listItemERC1155(
        address collection,
        uint256 tokenId,
        uint256 quantity,
        uint256 price
    )
        external
        onlyAllowedToBeListed(collection)
        whenNotPaused
        onlyNonBlacklistedUsers
        nonReentrant
    {
        _listItem(collection, tokenId, quantity, price);

        emit ItemListedERC1155(
            msg.sender,
            collection,
            tokenId,
            price,
            quantity
        );
    }

    function updateListItemERC1155(
        address collection,
        uint256 tokenId,
        uint256 quantity,
        uint256 price
    )
        external
        onlyAllowedToBeListed(collection)
        whenNotPaused
        onlyNonBlacklistedUsers
        nonReentrant
    {
        _listItem(collection, tokenId, quantity, price);

        emit ItemUpdatedERC1155(
            msg.sender,
            collection,
            tokenId,
            price,
            quantity
        );
    }

    function removeItemERC1155(address collection, uint256 tokenId)
        external
        nonReentrant
    {
        if (collection == address(0)) revert RejectedNullishAddress();

        delete fixedPriceListingsERC1155[collection][tokenId][msg.sender];

        emit ItemRemovedERC1155(msg.sender, collection, tokenId);
    }

    function purchaseItemERC1155(
        address collection,
        uint256 tokenId,
        uint256 quantity,
        address seller,
        address to
    ) external payable nonReentrant {
        if (
            collection == address(0) || to == address(0) || seller == address(0)
        ) revert RejectedNullishAddress();

        FixedPriceListingERC1155 memory item = fixedPriceListingsERC1155[
            collection
        ][tokenId][seller];

        if (item.quantity == 0 || item.price == 0)
            revert Exchange_Listing_Not_Found();

        if (item.quantity != quantity) {
            revert Exchange_Unmatched_Quantity(item.quantity, quantity);
        }

        if (msg.value != item.price) revert Exchange_Wrong_Price_Value();

        delete fixedPriceListingsERC1155[collection][tokenId][seller];

        ExchangeCore._executeETHPayment(
            collection,
            tokenId,
            seller,
            item.price
        );

        IERC1155(collection).safeTransferFrom(
            seller,
            to,
            tokenId,
            item.quantity,
            ""
        );

        if (address(rewardsManager) != address(0)) {
            rewardsManager.purchaseEvent(
                seller,
                to,
                item.price,
                collection,
                tokenId,
                quantity
            );
        }

        emit ItemPurchasedERC1155(
            msg.sender,
            seller,
            collection,
            tokenId,
            quantity,
            item.price
        );
    }

    function makeOfferERC1155(
        address collection,
        uint256 tokenId,
        uint128 quantity,
        uint128 validityDuration,
        uint256 offerValue
    ) external nonReentrant {
        uint256 expiresAt = _updateOffer(
            collection,
            tokenId,
            quantity,
            validityDuration,
            offerValue
        );

        emit OfferMadeERC1155(
            msg.sender,
            collection,
            tokenId,
            quantity,
            offerValue,
            validityDuration,
            expiresAt
        );
    }

    function cancelOfferERC1155(address collection, uint256 tokenId)
        external
        nonReentrant
    {
        if (collection == address(0)) revert RejectedNullishAddress();

        delete offersERC1155[collection][tokenId][msg.sender];

        emit OfferCancelledERC1155(msg.sender, collection, tokenId);
    }

    function updateOfferERC1155(
        address collection,
        uint256 tokenId,
        uint128 quantity,
        uint128 validityDuration,
        uint256 offerValue
    ) external nonReentrant {
        uint256 expiresAt = _updateOffer(
            collection,
            tokenId,
            quantity,
            validityDuration,
            offerValue
        );

        emit OfferUpdatedERC1155(
            msg.sender,
            collection,
            tokenId,
            quantity,
            offerValue,
            validityDuration,
            expiresAt
        );
    }

    function acceptOfferERC1155(
        address beneficiary,
        address collection,
        uint256 tokenId,
        uint128 quantity,
        uint256 offerValue
    ) external nonReentrant {
        if (collection == address(0)) revert RejectedNullishAddress();
        if (beneficiary == address(0)) revert RejectedNullishAddress();
        if (quantity == 0) revert Exchange_Rejected_Nullish_Quantity();

        OfferERC1155 memory offer = offersERC1155[collection][tokenId][
            beneficiary
        ];

        delete offersERC1155[collection][tokenId][beneficiary];
        delete fixedPriceListingsERC1155[collection][tokenId][msg.sender];

        if (offer.value != offerValue)
            revert Exchange_Wrong_Offer_Value(offer.value);

        if (offer.expiresAt < block.timestamp)
            revert Exchange_Expired_Offer(offer.expiresAt);

        if (quantity != offer.quantity)
            revert Exchange_Unmatched_Quantity(offer.quantity, quantity);

        ExchangeCore._executeWETHPayment(
            collection,
            tokenId,
            beneficiary,
            msg.sender,
            offerValue
        );
        IERC1155(collection).safeTransferFrom(
            msg.sender,
            beneficiary,
            tokenId,
            quantity,
            ""
        );

        if (address(rewardsManager) != address(0)) {
            rewardsManager.purchaseEvent(
                msg.sender,
                beneficiary,
                offer.value,
                collection,
                tokenId,
                quantity
            );
        }

        emit OfferAcceptedERC1155(
            beneficiary,
            msg.sender,
            collection,
            tokenId,
            quantity,
            offerValue
        );
    }

    function _updateOffer(
        address collection,
        uint256 tokenId,
        uint128 quantity,
        uint128 validityDuration,
        uint256 offerValue
    ) private returns (uint256 expiresAt) {
        if (collection == address(0)) revert RejectedNullishAddress();

        if (validityDuration == 0) revert Exchange_Rejected_Nullish_Duration();

        if (offerValue == 0) revert Exchange_Rejected_Nullish_Offer_Value();

        if (quantity == 0) revert Exchange_Rejected_Nullish_Quantity();

        uint256 wethAllowance = IWETH(WETH).allowance(
            msg.sender,
            address(this)
        );
        if (wethAllowance < offerValue)
            revert Exchange_Insufficient_WETH_Allowance(wethAllowance);

        uint128 _expiresAt = uint128(block.timestamp) + validityDuration;

        offersERC1155[collection][tokenId][msg.sender] = OfferERC1155({
            value: offerValue,
            quantity: quantity,
            expiresAt: _expiresAt
        });

        return _expiresAt;
    }

    function _listItem(
        address collection,
        uint256 tokenId,
        uint256 quantity,
        uint256 price
    ) private {
        if (price == 0) revert Exchange_Invalid_Nullish_Price();

        if (IERC1155(collection).balanceOf(msg.sender, tokenId) < quantity)
            revert Exchange_Not_The_Token_Owner();

        if (!IERC1155(collection).isApprovedForAll(msg.sender, address(this)))
            revert Exchange_Insufficient_Operator_Privilege();

        fixedPriceListingsERC1155[collection][tokenId][
            msg.sender
        ] = FixedPriceListingERC1155(quantity, price);
    }
}

