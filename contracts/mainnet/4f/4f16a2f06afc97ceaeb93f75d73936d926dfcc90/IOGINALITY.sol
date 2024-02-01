// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC721.sol";
import "./ERC721URIStorage.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./ECDSA.sol";
import "./Strings.sol";
import "./SafeMath.sol";

import "./ERC721RoyaltiesStorage.sol";
import "./Manageable.sol";

/// @custom:security-contact et@markuper.com
contract IOGINALITY is ERC721, ERC721URIStorage, ERC721RoyaltiesStorage, Ownable, Manageable {

    constructor(string memory name_, string memory symbol_, address manager_) ERC721(name_, symbol_) {
        _transferMangership(manager_);
    }

    /** BASE MINTING
     */
    function safeMint(address to, uint256 tokenId, string memory uri)
        public
    {
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
    }

    /** MINTING AND APPROVE TO IN ONE CALL
     * it useful when token minting by marketplace side to give the ability
     * to manage the token immediately
     * Case 1: we need to listing the token from admin zone,
     * we pass approveTo MarketManager contract address
     */
    function safeMint(address to, uint256 tokenId, string memory uri, address[] memory _feeRecipients, uint32[] memory _feeAmounts)
        public
    {
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        _setTokenRoyalties(tokenId, _feeRecipients, _feeAmounts);
    }

    /** MINTING AND APPROVE TO IN ONE CALL
     * it useful when token minting by marketplace side to give the ability
     * to manage the token immediately
     * Case 1: we need to listing the token from admin zone,
     * we pass approveTo MarketManager contract address
     */
    function safeMint(address to, uint256 tokenId, string memory uri, address approveTo)
        onlyManager public
    {
        safeMint(to, tokenId, uri);
        _setTokenURI(tokenId, uri);
        _approve(approveTo, tokenId);
    }

    /** MINTING AND APPROVE TO IN ONE CALL WITH ROYALTIES
     */
    function safeMint(address to, uint256 tokenId, string memory uri, address approveTo, address[] memory _feeRecipients, uint32[] memory _feeAmounts)
        onlyManager public
    {
        safeMint(to, tokenId, uri);
        _setTokenURI(tokenId, uri);
        _setTokenRoyalties(tokenId, _feeRecipients, _feeAmounts);
        _approve(approveTo, tokenId);
    }

    // The following functions are overrides required by Solidity.

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }
}
