// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

library LibWeb3Domain {
    struct Order {
        string name;
        uint256 tokenId;
        string tokenURI;
        address owner;
        uint256 price;
        uint256 timestamp;
    }

    struct SimpleOrder {
        string name;
        address owner;
        uint256 price;
        uint256 timestamp;
    }

    struct ReclaimNodeRequest {
        bytes32 node;
        address owner;
        uint256 timestamp;
    }

    bytes32 public constant ORDER_TYPEHASH =
        keccak256("Order(string name,uint256 tokenId,string tokenURI,address owner,uint256 price,uint256 timestamp)");
    bytes32 public constant SIMPLE_ORDER_TYPEHASH =
        keccak256("SimpleOrder(string name,address owner,uint256 price,uint256 timestamp)");
    bytes32 public constant RECLAIM_NODE_TYPEHASH =
        keccak256("ReclaimNodeRequest(bytes32 node,address owner,uint256 timestamp)");

    function getHash(Order calldata order) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    ORDER_TYPEHASH,
                    keccak256(bytes(order.name)),
                    order.tokenId,
                    keccak256(bytes(order.tokenURI)),
                    order.owner,
                    order.price,
                    order.timestamp
                )
            );
    }

    function getHash(SimpleOrder calldata order) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    SIMPLE_ORDER_TYPEHASH,
                    keccak256(bytes(order.name)),
                    order.owner,
                    order.price,
                    order.timestamp
                )
            );
    }

    function getHash(ReclaimNodeRequest calldata request) internal pure returns (bytes32) {
        return keccak256(abi.encode(RECLAIM_NODE_TYPEHASH, request.node, request.owner, request.timestamp));
    }
}

