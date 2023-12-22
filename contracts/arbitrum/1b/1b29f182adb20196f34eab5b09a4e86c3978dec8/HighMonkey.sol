// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./ERC721.sol";

contract HighMonkey is ERC721 {
    address public signerAddress = 0x2c2A87FfaeF3C6A063675bCBb3312A47b7e24BF9;

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC721(_name, _symbol) {}

    function mint(address to, uint256 tokenId, bytes memory signature) public {
        // Verify the signature
        require(isValidSignature(keccak256(abi.encodePacked(to, tokenId)), signature), "Invalid signature");

        // Mint the NFT
        _mint(to, tokenId);
    }

    function isValidSignature(bytes32 hash, bytes memory signature)
        public
        view
        returns (bool)
    {
        bytes32 r;
        bytes32 s;
        uint8 v;

        // Check the signature length
        if (signature.length != 65) {
            return false;
        }

        // Divide the signature in r, s and v variables
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        // Version of signature should be 27 or 28, but 0 and 1 are also possible versions
        if (v < 27) {
            v += 27;
        }

        // If the version is correct return the signer address
        if (v != 27 && v != 28) {
            return false;
        } else {
            // ecrecover returns the address that was used to sign the hash
            return ecrecover(hash, v, r, s) == signerAddress;
        }
    }
}

