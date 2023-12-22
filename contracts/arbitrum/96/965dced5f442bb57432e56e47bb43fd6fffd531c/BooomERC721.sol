pragma solidity ^0.8.10;

import "./ERC721Enumerable.sol";
import "./Ownable.sol";

// SPDX-License-Identifier: MIT
contract Booom721 is ERC721Enumerable, Ownable {

    string _baseTokenURI;
    uint256 public _price = 0 ether;
    bool public _paused = true;

    // withdraw addresses
    address _withdrawAddress = 0x2a17eDC1a12bAF6eB68Df4aC2d76931d2D5F58c3;

    constructor() ERC721("Booom NFT", "BooomNFT")  {
        setBaseURI("https://cloudflare-ipfs.com/ipfs/QmfDtv1KGPtLeHJBLoP88ktxdQEbp3FzenCnmFW4E3S7gQ/");
    }

    function mint() public payable {
        uint256 supply = totalSupply();
        require(supply + 1 < 10000, "Exceeds maximum ERC721 supply");

        _safeMint(msg.sender, supply + 1);
    }

    function withdrawAll() public payable onlyOwner {
        require(payable(_withdrawAddress).send(address(this).balance));
    }

    function setBaseURI(string memory baseURI) public onlyOwner {
        _baseTokenURI = baseURI;
    }


    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function allMoney() public view returns (uint256) {
        return address(this).balance;
    }
}
