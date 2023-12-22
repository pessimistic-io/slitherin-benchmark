// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC1155.sol";
import "./IERC721.sol";
import "./Types.sol";

/* @title the interface for nft point store
 * @dev the nft store which support owner to sell nft which is priced by point
 **/
interface INFTStore {
    //********************EVENT*******************************//

    event NftListed(uint64 originChain, bool isErc1155, address indexed nft, uint256 tokenId, uint64 price);
    event NftBought(
        uint64 originChain,
        bool isErc1155,
        address indexed nft,
        uint256 tokenId,
        uint64 price,
        address buyer
    );

    //********************FUNCTION*******************************//
    /*
     * @dev sell erc721 by owner
     * @notice only permitted by owner
     **/
    function listNft(uint64 originChain, bool isErc1155, address nft, uint256 tokenId, uint64 point) external;

    function buyNftAndWithdraw(uint64 originChain, bool isErc1155, address nft, uint256 tokenId) external payable;

    function buyNft(uint64 originChain, bool isErc1155, address addr, uint256 tokenId, bool withdraw) external payable;

    /// @dev get price of a nft
    function getPrice(
        uint64 originChain,
        bool isErc1155,
        address addr,
        uint256 tokenId
    ) external view returns (uint256);
}

