// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;
import "./NFT.sol";
import "./ISubscription.sol";

contract Subscription is NFT, ISubscription {
    /// @dev The token ID metadata
    mapping(uint256 => Meta) public metas;

    constructor() NFT("xfans.vip SUBSCRIPTION-NFT", "XFANS-SUB") {}

    function mint(
        address to,
        address _author,
        uint128 _startAt,
        uint128 _expireAt
    ) external override onlyOperator returns (uint tokenId) {
        _mint(to, (tokenId = nextId()));

        metas[tokenId] = Meta({
            author: _author,
            start: _startAt,
            expire: _expireAt
        });
    }
}

