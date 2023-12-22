// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./ERC721URIStorage.sol";

contract CyberEvo is ERC721URIStorage{
    uint public tokenCount;
    address public deployer;
    uint public mintFee = 30000000000000000;

    string private ipfsHash;

    event Minted(address to, uint tokenId);
    

    receive() external payable{}

    constructor(string memory _ipfsHash) ERC721("CyberEvo", "CBE"){
        deployer = msg.sender;
        ipfsHash = _ipfsHash;
        
    }

    function mint() public payable returns(uint) {
        require(msg.value >= mintFee, "CyberEvo: insufficient funds for mint");
        // increment token
        tokenCount++;
        uint currentToken = tokenCount;

        // mint token id to user
        _mint(msg.sender, currentToken);

        // encode the full ipfs and token uri
        string memory tokenUri = string(abi.encodePacked(ipfsHash, Strings.toString(currentToken), ".json"));

        // set the token uri to the current token
        _setTokenURI(currentToken, tokenUri);

        emit Minted(msg.sender, currentToken);
        
        // return the current token number
        return currentToken;

    }



    // mint fee setter
    function setMintFee(uint newFee) public returns(uint) {
        require(msg.sender == deployer, "CyberEvo: Deployer only function");
        return mintFee = newFee;

    }   


    // withdraw contract funds

    function withdrawFunds() public returns(bool){
        require(msg.sender == deployer, "CyberEvo: Deployer only function");
        uint256 balance = address(this).balance;
        require(balance > 0, "Contract has no balance to withdraw");

        (bool success, ) = payable(deployer).call{value: balance}("");
        require(success, "Transfer failed");

        return success;

    }




    




}
