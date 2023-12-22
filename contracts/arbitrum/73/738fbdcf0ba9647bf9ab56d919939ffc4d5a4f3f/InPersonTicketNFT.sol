// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./Counters.sol";
import "./Ownable.sol";
import "./ERC721URIStorage.sol";
import "./console.sol";

contract InPersonTicketNFT is ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter public tokenIds;
    uint256 public ticketInventories;
    address public DaoTicketAddress;
    constructor(address addr) ERC721("InPersonTicketNFT", "NFT") {
        DaoTicketAddress = addr;
    }
    event NftEvent(address recipient, uint256 tokenId, string tokenURI);
    function mintNFT(address recipient)
        public  returns (uint256)
    {
        require(msg.sender == DaoTicketAddress, "Only DAO ticket contract can mint an InPersonTicketNFT!");
        require(tokenIds.current() <= ticketInventories, "There's no ticket left, sorry!");
        tokenIds.increment();
        uint256 newItemId = tokenIds.current();
        _mint(recipient, newItemId);
        // TODO: put a tokenURI placeholder for now!
        string memory tokenURI = "ipfs://QmNVJPswnRwHReptaBSrW81R43khRqDAdUMoZEtdnhM4mn";
        _setTokenURI(newItemId, tokenURI);
        emit NftEvent(recipient, newItemId, tokenURI);
        return newItemId;
    }

    function setTicketInventories(uint256 inventoriesNum) public onlyOwner {
        ticketInventories = inventoriesNum;
    }
}
