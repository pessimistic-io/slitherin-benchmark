// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./Strings.sol";
import "./IMerkle.sol";
import "./IAccessToken.sol";
import "./Signer.sol";
import "./console.sol";

contract AccessToken is Ownable, IAccessToken, Signer {
    using Strings for uint256;

    IMerkle immutable merkleTree; // additional merkle tree to store deposit addresses
    mapping(address => bool) public blacklistAddresses;
    mapping(uint256 => bool) public usedNonces;
    mapping(uint256 => bool) public accessTokens;

    uint256 public mintingFee;

    constructor(address merkleTreeInstance, uint256 _mintingFee) {
        merkleTree = IMerkle(merkleTreeInstance);
        mintingFee = _mintingFee;
    }

    function setMintingFee(uint256 _mintingFee) external onlyOwner {
        mintingFee = _mintingFee;
        emit MintingFeeChanged(mintingFee);
    }

    function addToken(SignatureData memory signatureData) public payable {
        require(
            !blacklistAddresses[msg.sender],
            "Address has been blacklisted"
        );
        require(
            !accessTokens[signatureData.accessKey],
            "User already has an access token"
        );
        require(msg.value == mintingFee, "incorrect minting fee");
        require(!usedNonces[signatureData.nonce], "nonce already used");
        usedNonces[signatureData.nonce] = true;

        bytes32 ethSignedMessageHash = getEthSignedMessageHash(
            signatureData.accessKey,
            block.chainid,
            address(this),
            signatureData.nonce
        );

        address signer = recoverSigner(ethSignedMessageHash, signatureData);
        require(
            signer == owner(),
            "Signature must be signed by the owner of the contract"
        );

        uint256 index = merkleTree.insert(signatureData.accessKey);
        accessTokens[signatureData.accessKey] = true;
        emit NewAccessKeyAdded(signatureData.accessKey, index, msg.sender);
    }

    function hasToken(uint256 accessKey) public view returns (bool) {
        return accessTokens[accessKey];
    }

    function rootHashExists(uint256 _root) public view returns (bool) {
        return merkleTree.rootHashExists(_root);
    }

    function getRootHash() public view returns (uint256) {
        return merkleTree.getRootHash();
    }

    function blacklistAccessKey(uint256 accessKey, uint256 index)
        public
        onlyOwner
    {
        merkleTree.findAndRemove(accessKey, index);
        delete accessTokens[accessKey];
        emit AccessKeyBlacklisted(accessKey);
    }

    function blacklistAddress(address _address) public onlyOwner {
        blacklistAddresses[_address] = true;
        emit AddressBlacklisted(_address);
    }

    function removeAddressFromBlacklist(address _address) public onlyOwner {
        delete blacklistAddresses[_address];
        emit AddressRemovedFromBlacklist(_address);
    }

    function withdraw() public onlyOwner {
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }
}

// console.log(
//     iToHex(
//         abi.encodePacked(
//             accessKey,
//             block.chainid,
//             signatureData.nonce
//         )
//     )
// );
// console.log(iToHex(signatureData.signedDataLength));
// console.log(
//     abi
//         .encodePacked(
//             accessKey,
//             block.chainid,
//             signatureData.nonce
//         )
//         .length
// );

