// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "./ERC721.sol";
import "./Ownable.sol";
import "./base64.sol";

contract UnstoppableFrog is ERC721 {
    string private s_imageURI;
    string constant svg =
        unicode'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="500" height="500"><rect width="100%" height="100%" fill="black" /><text x="0" y="15" fill="white">I am but a humble frog 🐸</text></svg>';

    constructor() ERC721("UnstoppableFrog", "UF") {
        s_imageURI = svgToImageURI();
        _safeMint(msg.sender, 0);
    }

    function svgToImageURI() public pure returns (string memory) {
        string memory baseURL = "data:image/svg+xml;base64,";
        string memory svgBase64Encoded = Base64.encode(bytes(string(abi.encodePacked(svg))));
        return string(abi.encodePacked(baseURL, svgBase64Encoded));
    }

    function _baseURI() internal pure override returns (string memory) {
        return "data:application/json;base64,";
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        return
            string(
                abi.encodePacked(
                    _baseURI(),
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"name":"',
                                name(), // You can add whatever name here
                                '", "description":"An NFT that has a tokenURI for a unstoppable website", ',
                                '"attributes": [{"trait_type": "coolness", "value": 100}], "image":"',
                                s_imageURI,
                                '"}'
                            )
                        )
                    )
                )
            );
    }
}

