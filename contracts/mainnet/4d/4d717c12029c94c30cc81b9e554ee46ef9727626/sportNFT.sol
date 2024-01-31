// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./Ownable.sol";
import "./ERC721Enumerable.sol";
import "./ERC165.sol";

interface IERC2981Royalties {
    function royaltyInfo(uint256 _tokenId, uint256 _value)
        external
        view
        returns (address _receiver, uint256 _royaltyAmount);
}

contract DSDNFTContract is ERC165, ERC721, ERC721Enumerable, Ownable {
    string private _baseURIextended;
    uint public _royaltyPercentage = 10;
    
    constructor() ERC721("Discover Sport Drop NFT", "DSD") {}

    function setBaseURI(string memory baseURI_) external onlyOwner() {
        _baseURIextended = baseURI_;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseURIextended;
    }

    function mint(uint256 n) public onlyOwner {
      uint supply = totalSupply();
      uint i;
      for (i = 0; i < n; i++) {
          _safeMint(msg.sender, supply + i);
      }
    }
    
    function royaltyInfo(
        uint256,
        uint256 _salePrice
    ) external view returns ( 
        address receiver, 
        uint256 royaltyAmount
    ) {
        uint256 fee = _salePrice * _royaltyPercentage / 100;
        return (owner(),  fee);
    }
    
    function setRoyaltyPercentage(uint newRoyaltyPercentage) public onlyOwner {
        require(newRoyaltyPercentage < 100, "Royalty percentage should be less than 100.");
        _royaltyPercentage = newRoyaltyPercentage;    
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, ERC721Enumerable, ERC165) returns (bool) {
        return interfaceId == type(IERC2981Royalties).interfaceId || super.supportsInterface(interfaceId);
    }
}
