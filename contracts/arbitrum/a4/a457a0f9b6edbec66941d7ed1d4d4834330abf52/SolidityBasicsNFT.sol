// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./ERC721.sol";
import "./base64.sol";

contract SolidityBasicsNFT is ERC721 {
    string public constant TOKEN_IMAGE_URI =
        "ipfs://QmdtW3ttRH2jmcb81yfcqqfBp48mnXD8NhqGiX53LK4JzR";
    uint256 private s_tokenCounter;

    bool[5] private s_booleanArray;

    constructor()
        ERC721("Patrick's Hardhat FreeCodeCamp Javascript Tutorial | Solidity Basics", "PHFCC")
    {
        s_tokenCounter = 0;
        s_booleanArray = [false, false, false, true, false];
    }

    /*
     * You need to pick the location of the "true" value in the array!
     * You can also pick the location of the "true" value for the next person :)
     */
    function mintNft(uint256 location, uint256 newLocation) public returns (uint256) {
        require(s_booleanArray[location] == true, "Wrong location picked!");

        s_booleanArray[location] = false;
        s_booleanArray[newLocation] = true;

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
                                '", "description":"This is for completing the Solidity Basics section of Patricks FreeCodeCamp Video! Awesome work!!", ',
                                '"attributes": [{"trait_type": "Remix Pro", "value": 100}], "image":"',
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

