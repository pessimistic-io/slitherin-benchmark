// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./ERC721Drop.sol";
import "./ECDSA.sol";

contract HighMonkey is ERC721Drop {
    address public signerAddress = 0x2c2A87FfaeF3C6A063675bCBb3312A47b7e24BF9;

    constructor(
        string memory _name,
        string memory _symbol,
        address _royaltyRecipient,
        uint128 _royaltyBps,
        address _primarySaleRecipient
    )
        ERC721Drop(
            _name,
            _symbol,
            _royaltyRecipient,
            _royaltyBps,
            _primarySaleRecipient
        )
    {}

    function mint(address to, uint256 tokenId, bytes memory signature) public {
        // Check the signature
        require(isValidSignature(keccak256(abi.encodePacked(to, tokenId)), signature), "Invalid signature");

        // Mint the NFT
        _mint(to, tokenId);
    }

    function isValidSignature(bytes32 hash, bytes memory signature)
        public
        view
        returns (bool)
    {
        return (ECDSA.recover(hash, signature) == signerAddress);
    }
}

