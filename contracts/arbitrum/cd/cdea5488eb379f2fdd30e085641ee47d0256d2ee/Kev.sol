// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./ERC721URIStorage.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./ERC721Burnable.sol";
import "./Counters.sol";

contract Kev is ERC721, ERC721Enumerable, ERC721URIStorage, Pausable, Ownable, ERC721Burnable {
    using Counters for Counters.Counter;
    uint256 public maxSupply;
    address payable public withdrawWallet;

    Counters.Counter private _tokenIdCounter;

    constructor() payable ERC721("Kev", "KEV") {
        maxSupply = 10000;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function safeMint(string memory _tokenURI) public payable whenNotPaused returns (uint) {
        require(_tokenIdCounter.current() <= maxSupply, 'sold out');
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, _tokenURI);
        return tokenId;
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        whenNotPaused
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
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

    function withdraw() external onlyOwner {
        (bool success, ) = withdrawWallet.call{value: address(this).balance}('');
        require(success, 'withdraw failed');
    }

    function setTokenURI(uint256 _tokenId, string memory _uri) public onlyOwner {
        _setTokenURI(_tokenId, _uri);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
