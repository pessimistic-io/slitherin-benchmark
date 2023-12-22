// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @notice EIP712 helpers
 * @dev Modified fork from Uniswap (https://github.com/Uniswap/permit2/blob/main/src/EIP712.sol)
 */
abstract contract EIP712 {
    // Cache the domain separator as an immutable value, but also store the chain id that it
    // corresponds to, in order to invalidate the cached domain separator if the chain id changes.
    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;
    uint256 private immutable _CACHED_CHAIN_ID;
    bytes32 private immutable _HASHED_NAME;

    bytes32 private constant _TYPE_HASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    constructor(string memory name) {
        _HASHED_NAME = keccak256(bytes(name));
        _CACHED_CHAIN_ID = block.chainid;
        _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator(_TYPE_HASH, _HASHED_NAME);
    }

    /// @notice Returns the domain separator for the current chain.
    /// @dev Uses cached version if chainid and address are unchanged from construction.
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return block.chainid == _CACHED_CHAIN_ID
            ? _CACHED_DOMAIN_SEPARATOR
            : _buildDomainSeparator(_TYPE_HASH, _HASHED_NAME);
    }

    /// @notice Builds a domain separator using the current chainId and contract address.
    function _buildDomainSeparator(bytes32 typeHash, bytes32 nameHash) private view returns (bytes32) {
        return keccak256(abi.encode(typeHash, nameHash, block.chainid, address(this)));
    }

    /// @notice Creates an EIP-712 typed data hash
    function _hashTypedData(bytes32 dataHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), dataHash));
    }

    /// @notice Verify signature for EIP-712 typed data
    function _verifySignature(bytes memory signature, bytes32 dataHash, address claimedSigner) internal view {
        SignatureVerification.verify(signature, _hashTypedData(dataHash), claimedSigner);
    }
}

/**
 * @dev Direct fork from Uniswap (https://github.com/Uniswap/permit2/blob/main/src/libraries/SignatureVerification.sol)
 */
library SignatureVerification {
    /// @notice Thrown when the passed in signature is not a valid length
    error InvalidSignatureLength();

    /// @notice Thrown when the recovered signer is equal to the zero address
    error InvalidSignature();

    /// @notice Thrown when the recovered signer does not equal the claimedSigner
    error InvalidSigner();

    /// @notice Thrown when the recovered contract signature is incorrect
    error InvalidContractSignature();

    bytes32 constant UPPER_BIT_MASK = (0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

    function verify(bytes memory signature, bytes32 digest, address claimedSigner) internal view {
        bytes32 r;
        bytes32 s;
        uint8 v;

        if (claimedSigner.code.length == 0) {
            if (signature.length == 65) {
                (r, s) = abi.decode(signature, (bytes32, bytes32));
                v = uint8(signature[64]);
            } else if (signature.length == 64) {
                // EIP-2098
                bytes32 vs;
                (r, vs) = abi.decode(signature, (bytes32, bytes32));
                s = vs & UPPER_BIT_MASK;
                v = uint8(uint256(vs >> 255)) + 27;
            } else {
                revert InvalidSignatureLength();
            }
            address signer = ecrecover(digest, v, r, s);
            if (signer == address(0)) revert InvalidSignature();
            if (signer != claimedSigner) revert InvalidSigner();
        } else {
            bytes4 magicValue = IERC1271(claimedSigner).isValidSignature(digest, signature);
            if (magicValue != IERC1271.isValidSignature.selector) revert InvalidContractSignature();
        }
    }
}

interface IERC1271 {
    /// @dev Should return whether the signature provided is valid for the provided data
    /// @param hash      Hash of the data to be signed
    /// @param signature Signature byte array associated with _data
    /// @return magicValue The bytes4 magic value 0x1626ba7e
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4 magicValue);
}

