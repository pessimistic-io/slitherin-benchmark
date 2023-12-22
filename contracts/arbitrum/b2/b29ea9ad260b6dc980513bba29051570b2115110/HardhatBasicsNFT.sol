// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./ERC721.sol";
import "./base64.sol";

error HardhatBasicsNFT__WrongValue();

contract HardhatBasicsNFT is ERC721 {
    string public constant TOKEN_IMAGE_URI =
        "ipfs://QmV5f4bSq3xmEwZLTar1tFUKh8kzWk6PrvwcQ7ooy8JFHY";
    uint256 private s_tokenCounter;
    uint256 private constant STARTING_NUMBER = 123;
    uint256 private constant STORAGE_LOCATION = 777;

    constructor()
        ERC721("Patrick's Hardhat FreeCodeCamp Javascript Tutorial | Hardhat Basics", "PHFCC")
    {
        s_tokenCounter = 0;
        assembly {
            sstore(STORAGE_LOCATION, STARTING_NUMBER)
        }
    }

    /*
     * To get this one, you have to pass the value in the 777th storage location
     * And then we use psuedo-randomness to pick to the next value.
     * This will test your hardhat and ethers chops!
     *
     * DONT DO RANDOMNESS LIKE THIS EVER. ITS BAD.
     *
     * Don't worry about the assembly stuff
     */
    function mintNft(uint256 valueAtStorageLocationSevenSevenSeven) public returns (uint256) {
        uint256 value;
        assembly {
            value := sload(STORAGE_LOCATION)
        }
        if (value != valueAtStorageLocationSevenSevenSeven) {
            revert HardhatBasicsNFT__WrongValue();
        }
        uint256 newValue = uint256(
            keccak256(abi.encodePacked(msg.sender, block.difficulty, block.timestamp))
        ) % 1000000;
        assembly {
            sstore(STORAGE_LOCATION, newValue)
        }

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
                                '", "description":"This is for completing the Hardhat Basics section of Patricks FreeCodeCamp Video! You a storage beast!!", ',
                                '"attributes": [{"trait_type": "Unbreak head (get it? Hardhat?)", "value": 100}], "image":"',
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

