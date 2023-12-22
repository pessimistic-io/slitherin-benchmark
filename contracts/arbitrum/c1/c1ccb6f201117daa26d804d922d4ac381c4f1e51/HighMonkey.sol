// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./Ownable.sol";

contract HighMonkey is ERC721, Ownable {
    address public signerAddress = 0x2c2A87FfaeF3C6A063675bCBb3312A47b7e24BF9;

    // Mapping from token ID to token URI
    mapping (uint256 => string) private _tokenURIs;

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC721(_name, _symbol) {}

    function mint(address to, uint256 tokenId, string memory tokenURI, bytes memory signature) public onlyOwner {
        // Verify the signature
        require(isValidSignature(keccak256(abi.encodePacked(to, tokenId, tokenURI)), signature), "Invalid signature");

        // Mint the NFT
        _mint(to, tokenId);

        // Set the token URI
        _setTokenURI(tokenId, tokenURI);
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

    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual {
        _tokenURIs[tokenId] = _tokenURI;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        return _tokenURIs[tokenId];
    }
}

