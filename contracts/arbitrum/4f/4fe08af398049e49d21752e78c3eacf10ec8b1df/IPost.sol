// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

interface IPost {
    struct Meta {
        address author;
        uint128 postId;
        uint128 nonce;//transfer counter
    }

    // mapping(uint256 => Meta) public metas;
    function metas(uint256 tokenId) external view returns ( address author,uint128 postId,uint128 nonce);

    function mint(
        address _author,
        uint128 postId,
        uint256 price
    ) external returns (uint256 tokenId);
}

