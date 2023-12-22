// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./Strings.sol";
import "./ERC721A.sol";

contract Arbifriends is Ownable, ERC721A {
    using Strings for uint256;

    uint256 public MAX_SUPPLY = 999;
    uint256 public mintPrice = 0.04 ether;
    string public baseURI;
    bool public publicsale = false;

    constructor(string memory _baseURI) ERC721A("Arbifriends", "ARBF") {
        baseURI = _baseURI;
    }

    modifier callerIsUser() {
        require(tx.origin == msg.sender, "The caller is another contract");
        _;
    }

    function mint(uint256 _quantity) external payable callerIsUser {
        require(publicsale, "Public Sale is not active");
        require(totalSupply() + _quantity <= MAX_SUPPLY, "Max supply exceeded");
        require(msg.value >= mintPrice * _quantity, "Not enought funds");
        _safeMint(msg.sender, _quantity);
    }

    function ownerMint(uint256 _quantity) public onlyOwner {
        require(totalSupply() + _quantity <= MAX_SUPPLY, "Max supply exceeded");
        _safeMint(msg.sender, _quantity);
    }

    function setBaseUri(string memory _baseURI) external onlyOwner {
        baseURI = _baseURI;
    }

    function setMintPrice(uint256 _newMintPrice) public onlyOwner {
        mintPrice = _newMintPrice;
    }

    function setMaxSupply(uint256 _maxSupply) public onlyOwner {
        MAX_SUPPLY = _maxSupply;
    }

    function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
        require(_exists(_tokenId), "URI query for nonexistent token");
        return string(abi.encodePacked(baseURI, _tokenId.toString(), ".json"));
    }

    function setPublicsale() public onlyOwner {
        publicsale = !publicsale;
    }

    function withdraw() public onlyOwner {
        (bool os, ) = payable(owner()).call{value: address(this).balance}("");
        require(os);
    }
}

