// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ERC721} from "./ERC721.sol";

contract RamenDAO is ERC721
 {
    uint256 public maxSupply = 25; 
    uint256 public totalSupply = 0;
    address private immutable owner;
    uint256 public price = 0.045 ether;
    uint256 public immutable memberPrice = 0.022 ether;
    mapping(uint256 => bool) private used; // keeps track of used CNC tokenIds 

    ICryptoNomadsClub private immutable CNC = ICryptoNomadsClub(0x951416CB5A9c5379Ae696AcB07CB8E25aEfAD370); //CNC address

    constructor() ERC721("RamenDAO @ ETHDenver by Crypto Nomads Club", "RAMEN") {
        owner = msg.sender;
    }

    function tokenURI(uint256) public pure override returns (string memory) {
        return "ipfs://QmajkArvdm8Eeqv1aT4Y74vXhYapbgLe9TsverbTBNECg8/";
    }

    function setMaxSupply(uint256 newMaxSupply) public {
        require(msg.sender == owner, "only owner");
        maxSupply = newMaxSupply;
    }

    function setPrice(uint256 newPrice) public {
        // changes public price. Member price is immutable
        require(msg.sender == owner, "only owner");
        price = newPrice;
    }

    function mint(uint256 amount) external payable {
        require(totalSupply + amount <= maxSupply, "No ramen left");
        require(
            amount <= 3,
            "Leave some ramen for the others ser"
        );
        require(price * amount <= msg.value, "Inflation ser. Add more ETH");

        for (uint256 i = 0; i < amount; i++) {
            _safeMint(msg.sender, totalSupply + i);
        }
        totalSupply += amount;
    }

    // allows holders of CNC tokens to mint at a discounted memberPrice
    // their tokenIds are retrieved from the CNC enumerable contract and marked as used 
    function memberMint(uint256 amount) external payable {
        require(totalSupply + amount <= maxSupply, "No ramen left");
        require(memberPrice * amount <= msg.value, "Inflation ser. Add more ETH");

        uint256 count = 0;
        for (uint256 i = 0; count < amount; i++) {
            // returns the CNC tokenIds the address holds. In order.
            // reverts if token doesn't exist. i.e
            uint256 tokenId = CNC.tokenOfOwnerByIndex(msg.sender, i);
            if(used[tokenId] != true){
                used[tokenId] = true;
                _safeMint(msg.sender, totalSupply + count++ + 100); // token Ids will look a bit weird but who cares
            }
        }
        totalSupply += amount;
    }

    function withdrawAll() external {
        payable(owner).transfer(address(this).balance);
    }

    // tokens with an ID over 100 can't be transferred
    function _beforeTokenTransfer(address from, address , uint256 tokenId, uint256 /*batchSize*/)
        internal pure
        override {
        require(tokenId < 100 || from == address(0), "discounted tokens are not transferrable");
    }
}

interface ICryptoNomadsClub {

    function tokenOfOwnerByIndex(address owner, uint256 index) 
        external   
        returns (uint256);

}
