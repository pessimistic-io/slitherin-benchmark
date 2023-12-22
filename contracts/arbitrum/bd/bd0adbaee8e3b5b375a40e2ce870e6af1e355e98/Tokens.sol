pragma solidity >=0.8.0 <0.9.0;

//SPDX-License-Identifier: MIT
library Tokens {
    error vcVersionNotValid();

    // the version header of the eip191
    bytes25 constant EIP191_VERSION_E_HEADER = "Ethereum Signed Message:\n";

    // the prefix of did, which is 'did::zk'
    bytes7 constant DID_ZK_PREFIX = bytes7("did:zk:");

    // the prefix of the attestation message, which is CredentialVersionedDigest
    bytes25 constant EIP191_CRE_VERSION_DIGEST_PREFIX =
        bytes25("CredentialVersionedDigest");

    // length 41
    bytes constant BINDING_MESSAGE_PART_1 =
        bytes(" will transfer the on-chain zkID Card to ");

    // length 81
    bytes constant BINDING_MESSAGE_PART_2 =
        bytes(
            " for use.\n\n I am aware that:\n If someone maliciously claims it on behalf, did:zk:"
        );

    // length 126
    bytes constant BINDING_MESSAGE_PART_3 =
        bytes(
            " will face corresponding legal consequences.\n If the Ethereum address is changed, all on-chain zklD Cards will be invalidated."
        );

    // length 42
    bytes constant BINDED_MESSAGE =
        bytes(" will accept the zkID Card sent by did:zk:");

    // the length of the CredentialVersionedDigest, which likes CredentialVersionedDigest0x00011b32b6e54e4420cfaf2feecdc0a15dc3fc0a7681687123a0f8cb348b451c2989
    // length 59, 25+ 2 + 32 = 59
    bytes2 constant EIP191_CRE_VERSION_DIGEST_LEN_V1 = 0x3539;

    // length 381, 7 + 42 + 41 + 42 + 81 + 42 + 126  = 381
    bytes3 constant BINDING_MESSAGE_LEN = 0x333831;

    // length 126, 42 + 42 + 42 = 126
    bytes3 constant BINDED_MESSAGE_LEN = 0x313236;

    bytes32 public constant MINT_TYPEHASH =
        keccak256(
            "signature(address recipient,bytes32 ctype,bytes32 programHash,uint64[] publicInput,bool isPublicInputUsedForCheck,bytes32 digest,address verifier,address attester,uint64[] output,uint64 issuanceTimestamp,uint64 expirationTimestamp,bytes2 vcVersion,string sbtLink)"
        );
    struct Token {
        address recipient;
        bytes32 ctype;
        bytes32 programHash;
        uint64[] publicInput;
        bool isPublicInputUsedForCheck;
        bytes32 digest;
        address verifier;
        address attester;
        bytes attesterSignature;
        uint64[] output;
        uint64 issuanceTimestamp;
        uint64 expirationTimestamp;
        bytes2 vcVersion;
        string sbtLink;
    }

    struct TokenOnChain {
        address recipient;
        bytes32 ctype;
        bytes32 programHash;
        uint64[] publicInput;
        bool isPublicInputUsedForCheck;
        bytes32 digest;
        address attester;
        uint64[] output;
        uint64 mintTimestamp;
        uint64 issuanceTimestamp;
        uint64 expirationTimestamp;
        bytes2 vcVersion;
        string sbtLink;
    }

    struct SBTWithUnnecePublicInput {
        uint64[] publicInput;
        uint256 tokenID;
    }


    function fillTokenOnChain(
        Token memory token,
        uint64 time,
        address realRecipient
    ) public pure returns (TokenOnChain memory tokenOnchain) {
        tokenOnchain.recipient = realRecipient;
        tokenOnchain.ctype = token.ctype;
        tokenOnchain.programHash = token.programHash;
        tokenOnchain.publicInput = token.publicInput;
        tokenOnchain.isPublicInputUsedForCheck = token.isPublicInputUsedForCheck;
        tokenOnchain.digest = token.digest;
        tokenOnchain.attester = token.attester;
        tokenOnchain.output = token.output;
        tokenOnchain.issuanceTimestamp = token.issuanceTimestamp;
        tokenOnchain.expirationTimestamp = token.expirationTimestamp;
        tokenOnchain.vcVersion = token.vcVersion;
        tokenOnchain.sbtLink = token.sbtLink;
        tokenOnchain.mintTimestamp = time;
    }

    function changeRecipient(
        TokenOnChain memory originTokenOnChain,
        address realRecipient
    ) public pure returns (TokenOnChain memory tokenOnchain){
        tokenOnchain.recipient = realRecipient;
        tokenOnchain.ctype = originTokenOnChain.ctype;
        tokenOnchain.programHash = originTokenOnChain.programHash;
        tokenOnchain.publicInput = originTokenOnChain.publicInput;
        tokenOnchain.isPublicInputUsedForCheck = originTokenOnChain.isPublicInputUsedForCheck;
        tokenOnchain.digest = originTokenOnChain.digest;
        tokenOnchain.attester = originTokenOnChain.attester;
        tokenOnchain.output = originTokenOnChain.output;
        tokenOnchain.issuanceTimestamp = originTokenOnChain.issuanceTimestamp;
        tokenOnchain.expirationTimestamp = originTokenOnChain.expirationTimestamp;
        tokenOnchain.vcVersion = originTokenOnChain.vcVersion;
        tokenOnchain.sbtLink = originTokenOnChain.sbtLink;
        tokenOnchain.mintTimestamp = originTokenOnChain.mintTimestamp;
    }

    function getRecipient(
        Token memory tokenDetail
    ) public pure returns (address) {
        return tokenDetail.recipient;
    }

    function verifyAttesterSignature(
        address attesterAssertionMethod,
        bytes memory attesterSignature,
        bytes32 digest,
        bytes2 vcVersion
    ) internal pure returns (bool) {
        bytes32 ethSignedMessageHash;

        if (vcVersion == 0x0001) {
            bytes memory versionedDigest = abi.encodePacked(vcVersion, digest);
            ethSignedMessageHash = keccak256(
                abi.encodePacked(
                    bytes1(0x19),
                    EIP191_VERSION_E_HEADER,
                    EIP191_CRE_VERSION_DIGEST_LEN_V1,
                    EIP191_CRE_VERSION_DIGEST_PREFIX,
                    versionedDigest
                )
            );
        } else {
            revert vcVersionNotValid();
        }
        return
            _recover(ethSignedMessageHash, attesterSignature) ==
            attesterAssertionMethod;
    }

    function verifySignature(
        Token memory tokenDetail,
        bytes memory signature,
        bytes32 domain_separator
    ) internal pure returns (bool) {
        bytes32 structHash = keccak256(
            abi.encode(
                MINT_TYPEHASH,
                tokenDetail.recipient,
                tokenDetail.ctype,
                tokenDetail.programHash,
                keccak256(abi.encodePacked(tokenDetail.publicInput)),
                tokenDetail.isPublicInputUsedForCheck,
                tokenDetail.digest,
                tokenDetail.verifier,
                tokenDetail.attester,
                keccak256(abi.encodePacked(tokenDetail.output)),
                tokenDetail.issuanceTimestamp,
                tokenDetail.expirationTimestamp,
                tokenDetail.vcVersion,
                keccak256(bytes(tokenDetail.sbtLink))
            )
        );

        bytes32 messageHash = keccak256(
            abi.encodePacked("\x19\x01", domain_separator, structHash)
        );

        if (_recover(messageHash, signature) != tokenDetail.verifier) {
            return false;
        }
        return true;
    }

    function verifyBindingSignature(
        address bindingAddress,
        address bindedAddress,
        bytes memory bindingSignature,
        bytes memory bindedSignature
    ) internal pure returns (bool) {
        bytes32 bindingMessageHash = keccak256(
            abi.encodePacked(
                bytes1(0x19),
                EIP191_VERSION_E_HEADER,
                BINDING_MESSAGE_LEN,
                DID_ZK_PREFIX,
                abi.encodePacked("0x", _getChecksum(bindingAddress)),
                BINDING_MESSAGE_PART_1,
                abi.encodePacked("0x", _getChecksum(bindedAddress)),
                BINDING_MESSAGE_PART_2,
                abi.encodePacked("0x", _getChecksum(bindingAddress)),
                BINDING_MESSAGE_PART_3
            )
        );
        bytes32 bindedMessageHash = keccak256(
            abi.encodePacked(
                bytes1(0x19),
                EIP191_VERSION_E_HEADER,
                BINDED_MESSAGE_LEN,
                abi.encodePacked("0x", _getChecksum(bindedAddress)),
                BINDED_MESSAGE,
                abi.encodePacked("0x", _getChecksum(bindingAddress))
            )
        );

        return (_recover(bindingMessageHash, bindingSignature) ==
            bindingAddress &&
            _recover(bindedMessageHash, bindedSignature) == bindedAddress);
    }

    /**
     * @dev parse the signature, and recover the signer address
     * @param hash, the messageHash which the signer signed
     * @param sig, the signature
     */
    function _recover(
        bytes32 hash,
        bytes memory sig
    ) internal pure returns (address) {
        bytes32 r;
        bytes32 s;
        uint8 v;

        // Check the signature length
        if (sig.length != 65) {
            return (address(0));
        }

        // Divide the signature in r, s and v variables
        // ecrecover takes the signature parameters, and the only way to get them
        // currently is to use assembly.
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }

        // Version of signature should be 27 or 28, but 0 and 1 are also possible versions
        if (v < 27) {
            v += 27;
        }

        // If the version is correct return the signer address
        if (v != 27 && v != 28) {
            return (address(0));
        } else {
            // solium-disable-next-line arg-overflow
            return ecrecover(hash, v, r, s);
        }
    }

    /**
     * @dev Get a checksummed string hex representation of an account address.
     * @param account address The account to get the checksum for.
     */
    function _getChecksum(
        address account
    ) internal pure returns (string memory accountChecksum) {
        // call internal function for converting an account to a checksummed string.
        return _toChecksumString(account);
    }

    function _toChecksumString(
        address account
    ) internal pure returns (string memory asciiString) {
        // convert the account argument from address to bytes.
        bytes20 data = bytes20(account);

        // create an in-memory fixed-size bytes array.
        bytes memory asciiBytes = new bytes(40);

        // declare variable types.
        uint8 b;
        uint8 leftNibble;
        uint8 rightNibble;
        bool leftCaps;
        bool rightCaps;
        uint8 asciiOffset;

        // get the capitalized characters in the actual checksum.
        bool[40] memory caps = _toChecksumCapsFlags(account);

        // iterate over bytes, processing left and right nibble in each iteration.
        for (uint256 i = 0; i < data.length; i++) {
            // locate the byte and extract each nibble.
            b = uint8(uint160(data) / (2 ** (8 * (19 - i))));
            leftNibble = b / 16;
            rightNibble = b - 16 * leftNibble;

            // locate and extract each capitalization status.
            leftCaps = caps[2 * i];
            rightCaps = caps[2 * i + 1];

            // get the offset from nibble value to ascii character for left nibble.
            asciiOffset = _getAsciiOffset(leftNibble, leftCaps);

            // add the converted character to the byte array.
            asciiBytes[2 * i] = bytes1(leftNibble + asciiOffset);

            // get the offset from nibble value to ascii character for right nibble.
            asciiOffset = _getAsciiOffset(rightNibble, rightCaps);

            // add the converted character to the byte array.
            asciiBytes[2 * i + 1] = bytes1(rightNibble + asciiOffset);
        }

        return string(asciiBytes);
    }

    function _toChecksumCapsFlags(
        address account
    ) internal pure returns (bool[40] memory characterCapitalized) {
        // convert the address to bytes.
        bytes20 a = bytes20(account);

        // hash the address (used to calculate checksum).
        bytes32 b = keccak256(abi.encodePacked(_toAsciiString(a)));

        // declare variable types.
        uint8 leftNibbleAddress;
        uint8 rightNibbleAddress;
        uint8 leftNibbleHash;
        uint8 rightNibbleHash;

        // iterate over bytes, processing left and right nibble in each iteration.
        for (uint256 i; i < a.length; i++) {
            // locate the byte and extract each nibble for the address and the hash.
            rightNibbleAddress = uint8(a[i]) % 16;
            leftNibbleAddress = (uint8(a[i]) - rightNibbleAddress) / 16;
            rightNibbleHash = uint8(b[i]) % 16;
            leftNibbleHash = (uint8(b[i]) - rightNibbleHash) / 16;

            characterCapitalized[2 * i] = (leftNibbleAddress > 9 &&
                leftNibbleHash > 7);
            characterCapitalized[2 * i + 1] = (rightNibbleAddress > 9 &&
                rightNibbleHash > 7);
        }
    }

    function _getAsciiOffset(
        uint8 nibble,
        bool caps
    ) internal pure returns (uint8 offset) {
        // to convert to ascii characters, add 48 to 0-9, 55 to A-F, & 87 to a-f.
        if (nibble < 10) {
            offset = 48;
        } else if (caps) {
            offset = 55;
        } else {
            offset = 87;
        }
    }

    // based on https://ethereum.stackexchange.com/a/56499/48410
    function _toAsciiString(
        bytes20 data
    ) internal pure returns (string memory asciiString) {
        // create an in-memory fixed-size bytes array.
        bytes memory asciiBytes = new bytes(40);

        // declare variable types.
        uint8 b;
        uint8 leftNibble;
        uint8 rightNibble;

        // iterate over bytes, processing left and right nibble in each iteration.
        for (uint256 i = 0; i < data.length; i++) {
            // locate the byte and extract each nibble.
            b = uint8(uint160(data) / (2 ** (8 * (19 - i))));
            leftNibble = b / 16;
            rightNibble = b - 16 * leftNibble;

            // to convert to ascii characters, add 48 to 0-9 and 87 to a-f.
            asciiBytes[2 * i] = bytes1(
                leftNibble + (leftNibble < 10 ? 48 : 87)
            );
            asciiBytes[2 * i + 1] = bytes1(
                rightNibble + (rightNibble < 10 ? 48 : 87)
            );
        }

        return string(asciiBytes);
    }
}

