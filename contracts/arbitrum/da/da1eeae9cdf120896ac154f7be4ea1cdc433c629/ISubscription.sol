// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

interface ISubscription {
    struct Meta {
        address author;
        uint128 start;
        uint128 expire;
    }

    // mapping(uint256 => Meta) public metas;
    function metas(uint256 tokenId) external view returns ( address author,uint128 start,uint128 expire);

    function mint(
        address to,
        address _author,
        uint128 _startAt,
        uint128 _expireAt
    ) external returns (uint256 tokenId);


}

