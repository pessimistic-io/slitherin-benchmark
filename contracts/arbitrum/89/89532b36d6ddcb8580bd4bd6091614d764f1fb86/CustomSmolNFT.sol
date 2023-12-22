// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;
import "./AccessControl.sol";
import "./Counters.sol";
import "./ERC721URIStorage.sol";
import "./ERC721Enumerable.sol";
import "./ERC721.sol";
import "./SafeERC20.sol";
import "./IERC721.sol";

import "./console.sol";

contract CustomSmolNFT is ERC721Enumerable, ERC721URIStorage, AccessControl {
    using SafeERC20 for IERC20;

    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    address marketplaceAddress;
    address smolBrainAddress;
    uint256 public MAX_NFT;

    constructor(address _marketplaceAddress, address _smolBrainAddress, uint256 maxNftSupply) ERC721("customSmol", "CSMOL") {
        marketplaceAddress = _marketplaceAddress;
        smolBrainAddress = _smolBrainAddress; 
        MAX_NFT = maxNftSupply;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, AccessControl, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function changeKey(address key) public onlyRole(DEFAULT_ADMIN_ROLE) {
            smolBrainAddress = key;
    }

    function changeURI(uint256 tokenId, string memory _tokenURI) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setTokenURI(tokenId,_tokenURI);
    }


    function createToken(string memory _tokenURI) public returns (uint) {
        require(_tokenIds.current() <= MAX_NFT);
        
        IERC721 key = IERC721(smolBrainAddress);
            
        require(key.balanceOf(msg.sender) > 0, "No Smol, no mint");

        uint256 tokenId = _tokenIds.current();
        _tokenIds.increment();

        _mint(msg.sender, tokenId);
        _setTokenURI(tokenId, _tokenURI);
        setApprovalForAll(marketplaceAddress, true);
        return tokenId;
    }

    function ownerMint(string memory _tokenURI) public onlyRole(DEFAULT_ADMIN_ROLE) returns (uint) {
        require(_tokenIds.current() <= MAX_NFT);

        uint256 tokenId = _tokenIds.current();
        _tokenIds.increment();

        _mint(msg.sender, tokenId);
        _setTokenURI(tokenId, _tokenURI);
        setApprovalForAll(marketplaceAddress, true);
        return tokenId;
    }

        function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

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
