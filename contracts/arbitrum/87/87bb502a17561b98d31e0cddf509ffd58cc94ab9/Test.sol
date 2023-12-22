pragma solidity ^0.8.20;

import "./ERC721.sol";
import "./Base64.sol";

contract Test is ERC721 {
    uint256 tokenId = 0;

    string image;

    constructor() ERC721("Mock NFT", "VEMNFT") {}

    function mint(address to) public {
        ++tokenId;
        uint _tokenId = tokenId;
        _mint(to, _tokenId);
    }


    function tokenURI(
        uint256 _tokenId
    ) public view override returns (string memory) {
        return image;
    }

    function setImge(string memory _image) public {
        image = _image;
    }
}

