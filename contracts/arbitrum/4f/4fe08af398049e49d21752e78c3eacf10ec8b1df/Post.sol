// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;
import "./NFT.sol";
import "./IPost.sol";

contract Post is NFT, IPost {
    /// @dev The token ID metadata
    mapping(uint256 => Meta) public metas;

    constructor() NFT("xfans.vip POST-NFT", "XFANS-POST") {}

    function mint(
        address _author,
        uint128 _postId,
        uint256 _price
    ) external override onlyOperator returns (uint256 tokenId) {
        _mint(_author, (tokenId = nextId()));

        //50000gas
        //203142 201003 postId=>uint128
        metas[tokenId] = Meta({author: _author, postId: _postId,nonce:0});

        prices[tokenId] = _price;
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 
    ) internal override {
        if(to!=address(0) && from!=address(0)){
            //update transfer nonce
            metas[firstTokenId].nonce++;
        }
    }

}

