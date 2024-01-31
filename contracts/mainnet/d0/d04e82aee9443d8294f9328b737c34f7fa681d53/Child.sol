// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;
import "./Counters.sol";
import "./ERC721.sol";
import "./ERC721URIStorage.sol";
import "./Ownable.sol";
// import "./ALTNFT.sol";

contract Child is ERC721URIStorage {
    constructor(string memory _name,string memory _inis) ERC721(_name,_inis){
    }
    using Strings for uint256;
    using Counters for Counters.Counter; 
    Counters.Counter private _tokenIds;

    function createToken(address user,string memory tokenURI) public returns (uint) {
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();

        _mint(user, newItemId);
        _setTokenURI(newItemId, tokenURI);

        return newItemId;
    }
}
