// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./AccessControl.sol";
import "./NFT721.sol";


import "./console.sol";

contract MintingStation is AccessControl {
    NFT721 public nft721;
    mapping(address => bool) public whiteListSigner;

    // bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    event mintCollectibleEvent(address tokenReceiver, string URI, uint256 tokenId);

    // Modifier for minting roles
    // modifier onlyMinter() {
    //     require(hasRole(MINTER_ROLE, _msgSender()), "Not a minting role");
    //     _;
    // }

    // Modifier for admin roles
    modifier onlyOwner() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Not an admin role");
        _;
    }

    constructor(NFT721 _nft721) {
        nft721 = _nft721;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function setWhiteListSigner(address signer, bool status) public  onlyOwner{
        require(signer != address(0), "address(0)");
        whiteListSigner[signer] = status;
    }

    function checkWhiteListSigner(address signer) public view returns(bool) {
        return whiteListSigner[signer];
    }

    /**
     * @dev Mint NFTs from the NFT contract.aa
     */
    function mintCollectible(string memory URI, bytes memory signature) external returns (uint256) {
        address signer = verify(URI, signature);
        require(whiteListSigner[signer], "Invalid signer");
        uint256 tokenId = nft721.safeMint(msg.sender, URI);
        emit mintCollectibleEvent(msg.sender,URI, tokenId);
        return tokenId;
    }
    
    function recoverNonFungibleToken(address _token, uint256 _tokenId) external onlyOwner {
        nft721.recoverNonFungibleToken(_token, _tokenId);
    }

    function recoverToken(address _token) external onlyOwner {
        nft721.recoverToken(_token);
    }

    /**
     * @dev It transfers the ownership of the NFT contract
     * to a new address.
     * Only the main admins can set it.
     */
    function changeOwnershipNFTContract(address _newOwner) external onlyOwner {
        nft721.transferOwnership(_newOwner);
    }

    function verify(
        string memory _tokenURI,
        bytes memory signature
    ) internal pure returns (address) {
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n",
                uintToString(bytes(_tokenURI).length),
                _tokenURI
            )
        );

        return recoverSigner(ethSignedMessageHash, signature);
    }

    function recoverSigner(
        bytes32 _ethSignedMessageHash,
        bytes memory _signature
    ) internal pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);

        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    function splitSignature(
        bytes memory sig
    ) public pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "Invalid signature length");

        assembly {
            /*
            First 32 bytes stores the length of the signature

            add(sig, 32) = pointer of sig + 32
            effectively, skips first 32 bytes of signature

            mload(p) loads next 32 bytes starting at the memory address p into memory
            */

            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }
    }

    function uintToString(
        uint256 _value
    ) internal pure returns (string memory) {
        if (_value == 0) {
            return "0";
        }
        uint256 temp = _value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (_value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + (_value % 10)));
            _value /= 10;
        }
        return string(buffer);
    }
}

