// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

abstract contract AvoCoreEvents {
    /// @notice Emitted when the implementation is upgraded to a new logic contract
    event Upgraded(address indexed newImplementation);

    /// @notice Emitted when a message is marked as allowed smart contract signature
    event SignedMessage(bytes32 indexed messageHash);

    /// @notice Emitted when a previously allowed signed message is removed
    event RemoveSignedMessage(bytes32 indexed messageHash);

    /// @notice emitted when the avoSafeNonce in storage is increased through an authorized call to
    /// `occupyAvoSafeNonces()`, which can be used to cancel a previously signed request
    event AvoSafeNonceOccupied(uint256 indexed occupiedAvoSafeNonce);

    /// @notice emitted when a non-sequential nonce is occupied in storage through an authorized call to
    /// `useNonSequentialNonces()`, which can be used to cancel a previously signed request
    event NonSequentialNonceOccupied(bytes32 indexed occupiedNonSequentialNonce);

    /// @notice Emitted when a fee is paid through use of the `castAuthorized()` method
    event FeePaid(uint256 indexed fee);

    /// @notice Emitted when paying a fee reverts at the recipient
    event FeePayFailed(uint256 indexed fee);
}

