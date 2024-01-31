//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./MerkleProof.sol";
import "./VibeERC721.sol";
import "./SimpleFactory.sol";

contract VibeWhitelistSale {
    bytes32 public merkleRoot;
    string public ipfsHash;
    VibeERC721 public nft;

    function init(bytes calldata data) public payable {
        (address proxy, bytes32 merkleRoot_, string memory ipfsHash_) = abi
            .decode(data, (address, bytes32, string));

        require(nft == VibeERC721(address(0)), "Already initialized");

        merkleRoot = merkleRoot_;
        ipfsHash = ipfsHash_;
        nft = VibeERC721(proxy);
    }

    function mint(bytes32[] calldata merkleProof, uint256[] calldata tokenIds)
        public
        payable
    {
        require(
            MerkleProof.verify(
                merkleProof,
                merkleRoot,
                keccak256(abi.encodePacked(msg.sender, tokenIds))
            ),
            "invalid merkle proof"
        );
        for (uint256 i = 0; i < tokenIds.length; i++) {
            nft.mintWithId(msg.sender, tokenIds[i]);
        }
    }
}

