// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./ERC721.sol";
import "./IERC20.sol";
import "./base64.sol";

error FullStackBasicsNFT__TransferFailed();

contract FullStackBasicsNFT is ERC721 {
    string public constant TOKEN_IMAGE_URI =
        "ipfs://QmZnuDR8EfKaTbdbLHsgqVPPcp2GiFzjGrLQYCkYFAK9oQ";
    uint256 private s_tokenCounter;
    IERC20 private s_patrickToken;

    constructor(address patrickHardhatFreeCodeCampTokenAddress)
        ERC721("Patrick's Hardhat FreeCodeCamp Javascript Tutorial | Full Stack Basics", "PHFCC")
    {
        s_tokenCounter = 0;
        s_patrickToken = IERC20(patrickHardhatFreeCodeCampTokenAddress);
    }

    /*
     * To get this one, you have to pay the toll!
     * This is a full stack NFT tho huh... where did you find this contract?
     *
     * Don't forget to approve 😈
     *
     */
    function mintNft() public returns (uint256) {
        bool success = s_patrickToken.transferFrom(msg.sender, address(this), 1e18);
        if (!success) {
            revert FullStackBasicsNFT__TransferFailed();
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
                                '", "description":"This is for completing the Full Stack section of Patricks FreeCodeCamp Video! I hope to see you in the NEXT one!!!! DO YOU GET MY JOKE?????", ',
                                '"attributes": [{"trait_type": "Reactive (lmao)", "value": 100}], "image":"',
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

