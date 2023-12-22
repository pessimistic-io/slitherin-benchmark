// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

abstract contract AvoWalletEvents {
    /// @notice emitted when all actions are executed successfully
    /// caller = owner / AvoForwarder address. signer = address that triggered this execution (authority or owner)
    event CastExecuted(address indexed source, address indexed caller, address indexed signer, bytes metadata);

    /// @notice emitted if one of the executed actions fails. The reason will be prefixed with the index of the action.
    /// e.g. if action 1 fails, then the reason will be 1_reason
    /// if an action in the flashloan callback fails, it will be prefixed with two numbers:
    /// e.g. if action 1 is the flashloan, and action 2 of flashloan actions fails, the reason will be 1_2_reason.
    /// caller = owner / AvoForwarder address. signer = address that triggered this execution (authority or owner)
    event CastFailed(
        address indexed source,
        address indexed caller,
        address indexed signer,
        string reason,
        bytes metadata
    );

    /// @notice emitted when an allowed authority is added
    event AuthorityAdded(address indexed authority);

    /// @notice emitted when an allowed authority is removed
    event AuthorityRemoved(address indexed authority);
}

