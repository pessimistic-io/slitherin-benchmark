// contracts/Bridge.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./Ownable.sol";

import "./BytesLib.sol";

import "./Getters.sol";
import "./Setters.sol";
import "./Structs.sol";

import "./IWormhole.sol";

contract CATERC721Governance is CATERC721Getters, CATERC721Setters, Ownable {
    /// builds a prefixed hash to mimic the behavior of eth_sign.
    function prefixed(bytes32 _hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _hash));
    }

    /// signature methods.
    function splitSignature(
        bytes memory sig
    ) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        require(sig.length == 65);

        assembly {
            // first 32 bytes, after the length prefix.
            r := mload(add(sig, 32))
            // second 32 bytes.
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes).
            v := byte(0, mload(add(sig, 96)))
        }

        return (v, r, s);
    }

    function verifySignature(
        bytes32 message,
        bytes memory signature,
        address authority
    ) internal pure returns (bool) {
        (uint8 v, bytes32 r, bytes32 s) = splitSignature(signature);
        address recovered = ecrecover(message, v, r, s);
        if (recovered == authority) {
            return true;
        } else {
            return false;
        }
    }

    /// @dev verify owner is caller or the caller has valid owner signature
    modifier onlyOwnerOrOwnerSignature(
        CATERC721Structs.SignatureVerification memory signatureArguments
    ) {
        if (_msgSender() == owner()) {
            _;
        } else {
            bytes32 encodedHashData = prefixed(
                keccak256(
                    abi.encodePacked(signatureArguments.custodian, signatureArguments.validTill)
                )
            );
            require(signatureArguments.custodian == _msgSender(), "custodian can call only");
            require(signatureArguments.validTill > block.timestamp, "signed transaction expired");
            require(
                isSignatureUsed(signatureArguments.signature) == false,
                "cannot re-use signatures"
            );
            require(
                verifySignature(encodedHashData, signatureArguments.signature, owner()),
                "unauthorized signature"
            );
            setSignatureUsed(signatureArguments.signature);
            _;
        }
    }

    // Execute a RegisterChain governance message
    function registerChain(
        uint16 chainId,
        bytes32 tokenContract,
        CATERC721Structs.SignatureVerification memory signatureArguments
    ) public onlyOwnerOrOwnerSignature(signatureArguments) {
        setTokenImplementation(chainId, tokenContract);
    }

    function registerChains(
        uint16[] memory chainId,
        bytes32[] memory tokenContract,
        CATERC721Structs.SignatureVerification memory signatureArguments
    ) public onlyOwnerOrOwnerSignature(signatureArguments) {
        require(chainId.length == tokenContract.length, "Invalid Input");
        for (uint256 i = 0; i < tokenContract.length; i++) {
            setTokenImplementation(chainId[i], tokenContract[i]);
        }
    }

    // Execute a RegisterChain governance message
    function updateFinality(
        uint8 finality,
        CATERC721Structs.SignatureVerification memory signatureArguments
    ) public onlyOwnerOrOwnerSignature(signatureArguments) {
        setFinality(finality);
    }
}

