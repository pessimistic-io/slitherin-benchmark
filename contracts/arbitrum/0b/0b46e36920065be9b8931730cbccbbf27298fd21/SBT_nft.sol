// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ERC721Enumerable.sol";

contract SBT is Ownable, ERC721Enumerable {
    using Strings for uint256;
    string public myBaseURI;
    uint currentId = 1;
    mapping(uint => string) public uriMap;
    mapping(uint => uint) public cardIdMap;
    uint public mintedAmount;
    address public minter;

    constructor() ERC721('Yuri Credit Card', 'SBT') {
        minter = msg.sender;
    }

    function mint(address addr, uint cardId) external {
        require(msg.sender == minter, 'not minter');
        _mint(addr, currentId);
        cardIdMap[currentId] = cardId;
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

    function _safeTransfer(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) internal override {
    }

    function setBaseUri(string memory uri) public onlyOwner {
        myBaseURI = uri;
    }

    function setUriMap(uint cardId, string memory uri) public onlyOwner {
        uriMap[cardId] = uri;
    }

    function setUriMapBatch(uint[] memory cardId, string[] memory uri) public onlyOwner {
        for (uint i = 0; i < cardId.length; i++) {
            uriMap[cardId[i]] = uri[i];
        }
    }

    function tokenURI(uint256 tokenId_) override public view returns (string memory) {
        require(_exists(tokenId_), "nonexistent token");
        return string(uriMap[cardIdMap[tokenId_]]);
    }


    function burn(uint tokenId_) public returns (bool){
        require(_isApprovedOrOwner(_msgSender(), tokenId_), "burner isn't owner");
        _burn(tokenId_);
        return true;
    }

}
