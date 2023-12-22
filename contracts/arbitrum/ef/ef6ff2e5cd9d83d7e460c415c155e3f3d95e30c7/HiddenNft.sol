// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./ERC721.sol";
import "./base64.sol";

error HiddenNft__AlreadyMinted();
error HiddenNft__BadNumber();

contract HiddenNft is ERC721 {
    string public constant TOKEN_IMAGE_URI =
        "ipfs://QmajVabmhDv75MiqpLqfFG7DCTpLWFoyhEJJB4AQ3qxmdX";
    uint256 private s_tokenCounter;
    bool private s_minted;

    constructor()
        ERC721("Patrick's Hardhat FreeCodeCamp Javascript Tutorial | Hidden NFT", "HIDE")
    {
        s_tokenCounter = 0;
        s_minted = false;
    }

    /* And here is why pseudo-randomness is bad :) */
    function mintNft(uint256 number) public returns (uint256) {
        if (s_minted) {
            revert HiddenNft__AlreadyMinted();
        }
        uint256 value = uint256(
            keccak256(abi.encodePacked(msg.sender, block.difficulty, block.timestamp))
        ) % 1000000;

        // We are not reverting... be careful!!
        // if (number != value) {
        //     revert HiddenNft__BadNumber();
        // }

        if (number == value) {
            _safeMint(msg.sender, s_tokenCounter);
            s_tokenCounter = s_tokenCounter + 1;
            s_minted = true;
        }
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
                                '", "description":"You found the secret NFT from the CRAZY LONG HARDHAT FCC COURSE!!! There are only one of these. ", ',
                                '"attributes": [{"trait_type": "snooping & hacking", "value": 100}], "image":"',
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

