// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./ERC721Enumerable.sol";

contract Cocktail is ERC721Enumerable, Ownable {
    
    using SafeMath for uint256;
    
    uint256 public constant MAX_SUPPLY = 10000;
    uint256 private PRICE = 0.07 ether;
    uint256 public constant maxPurchase = 10;
    bool public activeSale = true;
    string public baseTokenURI;
    
    constructor(string memory baseURI) ERC721("Colorful Crypto Cocktails", "COCKTAIL") {
        setBaseURI(baseURI);
    }
    
    function reserveNFTs() public onlyOwner {
        require(totalSupply().add(10) <= MAX_SUPPLY, "Not enough NFTs to reserve");
     for (uint i = 0; i < 10; i++) {
          _mintNFT();
     }
    }
    
    function _baseURI() internal 
                    view 
                    virtual 
                    override 
                    returns (string memory) {
     return baseTokenURI;
    }
    
    function setBaseURI(string memory _baseTokenURI) public onlyOwner {
        baseTokenURI = _baseTokenURI;
    } 
    
    function mintNFTs(uint num) public payable {
        require(activeSale, "Sale is not active");
        require(totalSupply().add(num) <= MAX_SUPPLY, "Exceeds max supply");
        require(num <= maxPurchase, "Cannot mint more than 10");
        require(msg.value >= PRICE.mul(num), "Not enough ether to purchase NFTs.");
        for (uint i = 0; i < num; i++) {
            _mintNFT();
        }
    }

    function setPrice(uint256 _newPrice) public onlyOwner() {
        PRICE = _newPrice;
    }
    
    function getPrice() public view returns(uint256) {
        return PRICE;
    }
    
    function _mintNFT() private {
          _safeMint(msg.sender, totalSupply());
    }
    
    function setActiveSale(bool val) public onlyOwner {
        activeSale = val;
    }

    function tokensOfOwner(address _owner) 
         external 
         view 
         returns (uint[] memory) {
     uint tokenCount = balanceOf(_owner);
     uint[] memory tokensId = new uint256[](tokenCount);
     for (uint i = 0; i < tokenCount; i++) {
          tokensId[i] = tokenOfOwnerByIndex(_owner, i);
     }
     
     return tokensId;
    }
    
    function withdraw() public payable onlyOwner {
     uint balance = address(this).balance;
     require(balance > 0, "Ether balance zero");
     require(payable(msg.sender).send(balance));
    }
}
