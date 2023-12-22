// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "./Ownable.sol";
import {EIP712} from "./EIP712.sol";
import {ECDSA} from "./ECDSA.sol";
import {CallLib, Call} from "./Call.sol";
import {FsUtils} from "./FsUtils.sol";

// Signers (EOAs) are the only things that cross EVM chains as they have the same address on all chains.
// To represent an entity cross chains therefore requires a dedicated signer. However this is cumbersome
// to manage securely when the offchain entity is distributed (if the signer is hardware who possesses it, or
// the security risk of sharing the private key). Instead, ideally we want a multisig smart contract
// representing the entity but with a fixed address on all chains. We propose a simple proxy contract
// that can be deployed to a fixed address on all chains, and can be owned by a multisig wallet. This
// reduces the use of the key to infrequent initial setup for a new chain.

// Note: we could deploy this contract with a dedicated deployer key. However this means we must guarantee
// that deployment of this contract is always the first action on the chain for this key. Instead we
// opt for a pattern that only needs the dedicated key to sign offchain.
/// @title Offchain Entity Proxy
contract OffchainEntityProxy is Ownable, EIP712 {
    error InvalidSignature();

    bytes32 private constant TAKEOWNERSHIP_TYPEHASH =
        keccak256("TakeOwnership(address newOwner,uint256 nonce)");

    bytes32 private immutable entityName;

    uint256 public nonce;

    // Due to offchain signer address being part of the deployment bytecode, the address at which
    // this contract is deployed identifies the offchain signer.
    constructor(
        address offchainSigner,
        string memory _entityName
    ) EIP712("OffchainEntityProxy", "1") {
        _transferOwnership(offchainSigner);
        entityName = FsUtils.encodeToBytes32(bytes(_entityName));
    }

    /// @notice Take ownership of this contract.
    /// @dev By using signature based ownership transfer, we can ensure that the signer can be
    /// @dev purely offchain.
    /// @param signature Signature of the owner to be.
    function takeOwnership(bytes calldata signature) external {
        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(TAKEOWNERSHIP_TYPEHASH, msg.sender, nonce++))
        );

        address signer = ECDSA.recover(digest, signature);
        if (signer != owner()) revert InvalidSignature();

        _transferOwnership(msg.sender);
    }

    /// @notice Execute a batch of contract calls.
    /// @dev Allow the owner to execute arbitrary calls on behalf of the entity through this proxy
    /// @dev contract.
    /// @param calls An array of calls to execute.
    function executeBatch(Call[] memory calls) external payable onlyOwner {
        CallLib.executeBatch(calls);
    }

    /// @notice Get the name of the entity.
    /// @return The name of the entity.
    function name() external view returns (string memory) {
        return string(FsUtils.decodeFromBytes32(entityName));
    }
}

