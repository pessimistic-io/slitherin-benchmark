// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "./ERC721Upgradeable.sol";
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";

contract CyberTrophyNftUpgradable is Initializable, ERC721Upgradeable, OwnableUpgradeable {

    string private _baseUrl;
    address private _validSigner;

    function initialize(string memory name, string memory symbol, string memory baseUrl, address validSigner) public initializer {
        __ERC721_init(name, symbol);
        _baseUrl = baseUrl;
        _validSigner = validSigner;
        __Ownable_init();
    }


    // function verifies signature and creates a new nft
    function mintNftTrophyWithSignature(uint256 trophyId, bytes memory signature) public {
        // restore address from signature
        require(!_exists(trophyId), "Trophy already minted");
        require(_verify(trophyId, msg.sender, signature), "Signature is not valid");

        _safeMint(msg.sender, trophyId);
    }

    // Returns a URL for the storefront-level metadata for the contract 
    // as described at https://docs.opensea.io/docs/contract-level-metadata
    function contractURI() public view returns (string memory) {
        return string(abi.encodePacked(_baseUrl, "static-content/nft/cyber-trophy-nft-metadata.json"));
    }

    function _baseURI() internal view override returns (string memory) {
        return string(abi.encodePacked(_baseUrl, "nft/"));
    }

    function prepareNftRequestHash(uint256 trophyId, uint256 chainId, address contractAddress, address futureOwner) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(trophyId, chainId, contractAddress, futureOwner));
    }

    function _prepareEthSignedMessageHash(
        bytes32 _messageHash
    ) private pure returns (bytes32) {
        /*
        Signature is produced by signing a keccak256 hash with the following format:
        "\x19Ethereum Signed Message\n" + len(msg) + msg
        */
        return
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash)
            );
    }

    function _verify(
        uint256 trophyId,
        address _to,
        bytes memory signature
    ) private view returns (bool) {
        bytes32 messageHash = prepareNftRequestHash(trophyId, block.chainid, address(this), _to);
        bytes32 ethSignedMessageHash = _prepareEthSignedMessageHash(messageHash);

        return _recoverSigner(ethSignedMessageHash, signature) == _validSigner;
    }

    function _recoverSigner(bytes32 message, bytes memory sig)
       private
       pure
       returns (address)
    {
        uint8 v;
        bytes32 r;
        bytes32 s;
        (v, r, s) = _splitSignature(sig);
        return ecrecover(message, v, r, s);
    }
    function _splitSignature(bytes memory sig)
        private
        pure
        returns (uint8, bytes32, bytes32)
    {
        require(sig.length == 65);
        
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }
        return (v, r, s);
    }
}

