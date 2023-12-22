// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ERC721Enumerable.sol";

contract Kajama is Ownable, ERC721Enumerable {
    using Strings for uint256;
    string public myBaseURI;
    uint currentId = 1;
    mapping(uint => string) public uriMap;
    //    mapping(uint => sta) public cardIdMap;
    uint public maxMint = 20000;
    uint public mintedAmount;
    address public minter;

    constructor() ERC721('Kajama', 'Kajama') {
        minter = msg.sender;
    }

    function mint(address addr, string memory uri_) external {
        require(mintedAmount < maxMint, 'max mint');
        require(msg.sender == minter, 'not minter');
        _mint(addr, currentId);
        uriMap[currentId] = uri_;
        currentId ++;
        mintedAmount ++;
    }

    function setMinter(address _minter) public onlyOwner {
        minter = _minter;
    }


    function checkUserCardList(address player) public view returns (uint[] memory){
        uint tempBalance = balanceOf(player);
        uint token;
        uint[] memory list = new uint[](tempBalance);
        for (uint i = 0; i < tempBalance; i++) {
            token = tokenOfOwnerByIndex(player, i);
            list[i] = token;
        }

        return list;
    }

    function setBaseUri(string memory uri) public onlyOwner {
        myBaseURI = uri;
    }


    function setUriMapBatch(uint[] memory cardIds, string[] memory uris) public onlyOwner {
        require(cardIds.length == uris.length, 'length not match');
        for (uint i = 0; i < cardIds.length; i++) {
            uriMap[cardIds[i]] = uris[i];
        }
    }

    function tokenURI(uint256 tokenId_) override public view returns (string memory) {
        require(_exists(tokenId_), "nonexistent token");
        return string(uriMap[tokenId_]);
    }


    function burn(uint tokenId_) public returns (bool){
        require(_isApprovedOrOwner(_msgSender(), tokenId_), "burner isn't owner");
        _burn(tokenId_);
        return true;
    }

}
