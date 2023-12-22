// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721Base.sol";
import "./ECDSA.sol";

contract HighMonkey is ERC721Base {
    using ECDSA for bytes32;

    // This is your server's public key
    address public serverAddress = 0x2c2A87FfaeF3C6A063675bCBb3312A47b7e24BF9;

    constructor(
        string memory _name,
        string memory _symbol,
        address _royaltyRecipient,
        uint128 _royaltyBps,
        address _serverAddress
    ) ERC721Base(_name, _symbol, _royaltyRecipient, _royaltyBps) {
        serverAddress = _serverAddress;
    }

    function mint(address to, uint256 tokenId, string memory tokenURI, bytes memory signature) public {
        // This is the message to sign
        bytes32 message = keccak256(abi.encodePacked(to, tokenId, tokenURI));
        bytes32 hash = message.toEthSignedMessageHash();

        // Verify that the message's signer is the owner of the order
        address signer = hash.recover(signature);
        require(signer == serverAddress, "HighMonkey: invalid signature");

        // Mint the token
        _mint(to, tokenId);
        _setTokenURI(tokenId, tokenURI);
    }
}

