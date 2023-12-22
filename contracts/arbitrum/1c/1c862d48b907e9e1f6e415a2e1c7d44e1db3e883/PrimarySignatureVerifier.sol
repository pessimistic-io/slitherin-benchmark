/*
 * SPDX-License-Identifier: Apache-2.0
 */
pragma solidity ^0.8.8;

import "./OwnableUpgradeable.sol";
import "./SignatureCheckerUpgradeable.sol";
import "./ECDSAUpgradeable.sol";

import "./ICrossChainVerifier.sol";

contract PrimarySignatureVerifier is ICrossChainVerifier, OwnableUpgradeable {
    mapping(uint256 => address) private _signers;

    function initialize() public initializer {
        __Ownable_init();
    }

    function getSigners(
        uint256 _blockchainId
    ) external view override returns (address[] memory) {
        address[] memory signers = new address[](1);
        signers[0] = _signers[_blockchainId];

        return signers;
    }

    function supportedSigningAlgorithm(
        uint256 /* _blockchainId */
    ) external pure override returns (uint256) {
        // ECDSA SIGNATURE CODE
        return 1;
    }

    function decodeAndVerifyEvent(
        uint256 _blockchainId,
        bytes32 /* _eventSig */,
        bytes calldata _signedEventInfo,
        bytes calldata _signature
    ) external view override returns (bool) {
        address signer = _signers[_blockchainId];
        require(signer != address(0), "No registered signer for blockchain");

        bool valid = isSignatureValid(signer, _signedEventInfo, _signature);
        require(valid, "Invalid signature");

        return true;
    }

    function isSignatureValid(
        address _signer,
        bytes calldata _signedEventInfo,
        bytes calldata _signature
    ) public view returns (bool) {
        bytes32 messageHash = getMessageHash(_signedEventInfo);
        return
            SignatureCheckerUpgradeable.isValidSignatureNow(
                _signer,
                getSignedMessageHash(messageHash),
                _signature
            );
    }

    function getMessageHash(
        bytes calldata _signedEventInfo
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_signedEventInfo));
    }

    function getSignedMessageHash(bytes32 hash) public pure returns (bytes32) {
        return ECDSAUpgradeable.toEthSignedMessageHash(hash);
    }

    // ***************************************************************************
    // ******* Only Owner below here *********************************************
    // ***************************************************************************

    function updateSigner(
        uint256 _blockchainId,
        address _signer
    ) external onlyOwner {
        _signers[_blockchainId] = _signer;
    }
}

