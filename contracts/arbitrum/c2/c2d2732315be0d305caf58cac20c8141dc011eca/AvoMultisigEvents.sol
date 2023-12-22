// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

abstract contract AvoMultisigEvents {
    /// @notice emitted when all actions are executed successfully.
    /// caller = owner / AvoForwarder address. signers = addresses that triggered this execution
    event CastExecuted(address indexed source, address indexed caller, address[] signers, bytes metadata);

    /// @notice emitted if one of the executed actions fails. The reason will be prefixed with the index of the action.
    /// e.g. if action 1 fails, then the reason will be 1_reason
    /// if an action in the flashloan callback fails, it will be prefixed with with two numbers:
    /// e.g. if action 1 is the flashloan, and action 2 of flashloan actions fails, the reason will be 1_2_reason.
    /// caller = owner / AvoForwarder address. signers = addresses that triggered this execution
    /// Note If the signature was invalid, the `signers` array last set element is the signer that is not allowed
    event CastFailed(address indexed source, address indexed caller, address[] signers, string reason, bytes metadata);

    /// @notice emitted when a signer is added as Multisig signer
    event SignerAdded(address indexed signer);

    /// @notice emitted when a signer is removed as Multisig signer
    event SignerRemoved(address indexed signer);

    /// @notice emitted when the required signers count is updated
    event RequiredSignersSet(uint8 indexed requiredSigners);
}

