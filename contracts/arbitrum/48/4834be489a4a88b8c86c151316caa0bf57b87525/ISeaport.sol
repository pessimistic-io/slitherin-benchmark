// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface ISeaport {
    enum ItemType
    // 0: ETH on mainnet, MATIC on polygon, etc.
    {
        NATIVE,
        // 1: ERC20 items (ERC777 and ERC20 analogues could also technically work)
        ERC20,
        // 2: ERC721 items
        ERC721,
        // 3: ERC1155 items
        ERC1155,
        // 4: ERC721 items where a number of tokenIds are supported
        ERC721_WITH_CRITERIA,
        // 5: ERC1155 items where a number of ids are supported
        ERC1155_WITH_CRITERIA
    }

    enum OrderType
    // 0: no partial fills, anyone can execute
    {
        FULL_OPEN,
        // 1: partial fills supported, anyone can execute
        PARTIAL_OPEN,
        // 2: no partial fills, only offerer or zone can execute
        FULL_RESTRICTED,
        // 3: partial fills supported, only offerer or zone can execute
        PARTIAL_RESTRICTED,
        // 4: contract order type
        CONTRACT
    }

    struct ConsiderationItem {
        ItemType itemType;
        address token;
        uint256 identifierOrCriteria;
        uint256 startAmount;
        uint256 endAmount;
        address payable recipient;
    }

    struct OfferItem {
        ItemType itemType;
        address token;
        uint256 identifierOrCriteria;
        uint256 startAmount;
        uint256 endAmount;
    }

    struct OrderParameters {
        address offerer; // 0x00
        address zone; // 0x20
        OfferItem[] offer; // 0x40
        ConsiderationItem[] consideration; // 0x60
        OrderType orderType; // 0x80
        uint256 startTime; // 0xa0
        uint256 endTime; // 0xc0
        bytes32 zoneHash; // 0xe0
        uint256 salt; // 0x100
        bytes32 conduitKey; // 0x120
        uint256 totalOriginalConsiderationItems; // 0x140
            // offer.length                          // 0x160
    }

    struct OrderComponents {
        address offerer;
        address zone;
        OfferItem[] offer;
        ConsiderationItem[] consideration;
        OrderType orderType;
        uint256 startTime;
        uint256 endTime;
        bytes32 zoneHash;
        uint256 salt;
        bytes32 conduitKey;
        uint256 counter;
    }

    struct Order {
        OrderParameters parameters;
        bytes signature;
    }

    struct FullFillOrder {
        Order order;
        bytes32 fulfillerConduitKey;
    }

    function fulfillOrder(
        /**
         * @custom:name order
         */
        Order calldata,
        bytes32 fulfillerConduitKey
    ) external payable returns (bool fulfilled);

    /**
     * @notice Retrieve the current counter for a given offerer.
     *
     * @param offerer The offerer in question.
     *
     * @return counter The current counter.
     */
    function getCounter(address offerer) external view returns (uint256 counter);

    /**
     * @notice Retrieve the order hash for a given order.
     *
     * @custom:param order The components of the order.
     *
     * @return orderHash The order hash.
     */
    function getOrderHash(
        /**
         * @custom:name order
         */
        OrderComponents calldata
    ) external view returns (bytes32 orderHash);
}

