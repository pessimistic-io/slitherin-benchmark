pragma solidity ^0.8.9;

import "./ERC721.sol";
import "./Ownable.sol";

contract FuckBen is Ownable, ERC721 {
    constructor() ERC721("fuckben", "FB") {}

    string public baseURI;

    function mint(uint256 id) external onlyOwner {
        _mint(msg.sender, id);
    }

    function setBaseURI(string calldata _base) external onlyOwner  {
        baseURI = _base;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }
}
