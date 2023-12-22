// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./ERC721.sol";
import "./base64.sol";

contract BlockchainBasicsNFT is ERC721 {
    string public constant TOKEN_IMAGE_URI =
        "ipfs://QmNa2q358mBGwwvChnoqKanfoBpDC41uFF54Sr1KLw4Y8Z";
    uint256 private s_tokenCounter;

    constructor()
        ERC721("Patrick's Hardhat FreeCodeCamp Javascript Tutorial | Blockchain Basics", "PHFCC")
    {
        s_tokenCounter = 0;
    }

    function mintNft() public returns (uint256) {
        _safeMint(msg.sender, s_tokenCounter);
        s_tokenCounter = s_tokenCounter + 1;
        return s_tokenCounter;
    }

    function _baseURI() internal pure override returns (string memory) {
        return "data:application/json;base64,";
    }

    function tokenURI(
        uint256 /* tokenId */
    ) public view override returns (string memory) {
        return
            string(
                abi.encodePacked(
                    _baseURI(),
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"name":"',
                                name(),
                                '", "description":"This is for completing the Blockchain Basics section of Patricks FreeCodeCamp Video! The next get harder to mint :)", ',
                                '"attributes": [{"trait_type": "dopeness", "value": 100}], "image":"',
                                TOKEN_IMAGE_URI,
                                '"}'
                            )
                        )
                    )
                )
            );
    }

    function getTokenCounter() public view returns (uint256) {
        return s_tokenCounter;
    }
}

