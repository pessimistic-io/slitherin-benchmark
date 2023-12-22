// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "./Type.sol";

interface ITokenizePost {
    event PostPublished(
        address indexed owner,
        Type.PostPrice typePrice,
        uint256 sellPriceInUsd,
        string postId,
        uint256 tokenId,
        uint64 blockTimestamp
    );

    event PostBought(
        address indexed owner,
        address indexed buyer,
        Type.PostPrice typePrice,
        string postId,
        address tokenPay,
        uint256 amountInToken,
        uint256 amountInUsd,
        uint64 blockTimestamp,
        uint64 postSupply,
        uint256 tokenId
    );

    event PostStatusUpdated(
        address indexed owner,
        string postId,
        Type.PostStatus status,
        uint64 blockTimestamp
    );

    event PriceChanged(
        address indexed owner,
        string postId,
        uint256 newPrice,
        uint64 blockTimestamp
    );

    struct Post {
        uint256 tokenId;
        uint256 sellPrice;
        uint256 timePublish;
        uint256 postSupply;
        string postId;
        address owner;
        uint8 typePrice; // 0: fixed price, 1: floor price
        uint8 status; // 0: open, 1: hide, 2: delete
    }

    //    struct TokenizePostData {
    //        string postId;
    //        uint256 price;
    //        uint256 tokenId;
    //        address owner;
    //        uint8 postType; // 0: fixed price, 1: floor price
    //        uint64 blockTimestamp;
    //        address buyer;
    //    }

    struct Fee {
        Type.TypeFee typeFee;
        address receiver;
        uint256 feeInToken;
        uint256 feeInUsd;
    }

    event FeePaid(
        address buyer,
        address tokenPay,
        string postId,
        Fee[5] fees,
        uint64 blockTimestamp
    );

    function posts(
        string memory post_id
    )
        external
        view
        returns (
            uint256 tokenId,
            uint256 sellPrice,
            uint256 timePublish,
            uint256 postSupply,
            string memory postId,
            address owner,
            uint8 typePrice,
            uint8 status
        );

    //    function tokenizePosts(
    //        uint256 tokenIdPost
    //    )
    //        external
    //        view
    //        returns (
    //            string memory postId,
    //            uint256 price,
    //            uint256 tokenId,
    //            address owner,
    //            uint8 postType,
    //            uint64 blockTimestamp,
    //            address buyer
    //        );

    //    function mintPost(string memory postId, address receiver) external;

    //    function takePost(string memory postId, address receiver) external;

    //    function postsByOwner(address owner) external view returns (string[] memory);

    function getPricePost(string memory postId) external view returns (uint256);

    function changePrice(string memory postId, uint256 newPrice) external;

    function publishPost(
        Type.PostPrice typePrice,
        uint256 sellPrice,
        string memory postId
    ) external;
}

