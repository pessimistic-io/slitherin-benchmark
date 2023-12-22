// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "./ERC721A.sol";
import "./Ownable.sol";

contract InstinctToolERC721 is ERC721A, Ownable {
    string private baseURI;
    uint256 private mintPrice;
    uint256 private maxSupply;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseURI,
        uint _maxSupply,
        uint _mintPrice
    ) ERC721A(_name, _symbol) {
        baseURI = _baseURI;
        maxSupply = _maxSupply;
        mintPrice = _mintPrice;
    }

    function mint() public payable {
        require(totalSupply() + 1 <= maxSupply, "Max Supply exceeded");
        require(msg.value >= mintPrice, "Incorrect ether value");
        _safeMint(msg.sender, 1);
    }

    function setBaseURI(string memory _baseURI) public onlyOwner {
        baseURI = _baseURI;
    }

    function withdraw() public onlyOwner {
        (bool os, ) = payable(owner()).call{value: address(this).balance}("");
        require(os);
    }
}

