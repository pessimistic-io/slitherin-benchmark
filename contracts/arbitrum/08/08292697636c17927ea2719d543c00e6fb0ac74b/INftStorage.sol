// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.19;

import "./IdType.sol";
import "./StateType.sol";

abstract contract INftStorage {
    using StateTypeLib for StateType;

    uint8 public constant NFT_FLAG_LOCKED = 1; // flag

    uint16 public constant MAX_NFT_BOOST = 10; // mustn't be grater than uint16
    uint16 public constant MIN_NFT_BOOST = 1;

    uint16 public constant MAX_BUY_COUNT = 20;
    uint16 public constant MIN_BUY_COUNT = 1;

    uint16 public constant LB_RARITIES = 3;

    // we might have max 2^64 - 1 NFTs
    struct NFTDef {
        address owner;
        IdType left;
        StateType state;
        uint8 flags;
        uint16 boost;
        // 256 segment
        address approval;
        IdType right;
        uint32 entropy;
    }

    function _name() internal view virtual returns (string storage);
    function _symbol() internal view virtual returns (string storage);
    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI` and the `tokenId`. Empty
     * by default, can be overridden in child contracts.
     */
    function _baseURI() internal view virtual returns (string storage);
    function _baseURI(string memory baseUri) internal virtual;

    function _nft(IdType tokenId, NFTDef memory definition) internal virtual;
    function _nft(IdType tokenId) internal view virtual returns (NFTDef storage);
    function _deleteNft(IdType tokenId) internal virtual;

    function _operatorApprovals(address owner, address operator) internal view virtual returns (bool);
    function _operatorApprovals(address owner, address operator, bool value) internal virtual;
}

