// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./ERC721SignatureMint.sol";

contract HighMonkey is ERC721SignatureMint {
    address public burnAddress;
    address public signerAddress = 0x2c2A87FfaeF3C6A063675bCBb3312A47b7e24BF9;
    address public royaltyRecipient;

    constructor(
        string memory _name,
        string memory _symbol,
        address _royaltyRecipient,
        uint128 _royaltyBps,
        address _primarySaleRecipient,
        address _burnAddress
    )
        ERC721SignatureMint(
            _name,
            _symbol,
            _royaltyRecipient,
            _royaltyBps,
            _primarySaleRecipient
        )
    {
        burnAddress = _burnAddress;
        royaltyRecipient = _royaltyRecipient;
    }

    function setBurnAddress(address _burnAddress) external {
        require(msg.sender == royaltyRecipient, "Only the royalty recipient can set the burn address");
        burnAddress = _burnAddress;
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory signature
    ) public {
        require(isValidSignature(keccak256(abi.encodePacked(from, to, tokenId)), signature), "Invalid signature");
        super.transferFrom(from, to, tokenId);
    }

    function burnToken(uint256 tokenId) public {
        require(msg.sender == burnAddress, "Only the burn address can burn tokens");
        require(balanceOf(msg.sender) >= 420, "HighMonkey: Not enough tokens to burn");
        _burn(tokenId);
    }

    function isValidSignature(bytes32 hash, bytes memory signature)
        public
        view
        returns (bool)
    {
        return (ECDSA.recover(hash, signature) == signerAddress);
    }
}

