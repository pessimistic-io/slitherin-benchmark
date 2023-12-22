// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

abstract contract AvoMultisigErrors {
    /// @notice thrown when a method is called with invalid params (e.g. a zero address as input param)
    error AvoMultisig__InvalidParams();

    /// @notice thrown when a signature is not valid (e.g. not signed by enough allowed signers)
    error AvoMultisig__InvalidSignature();

    /// @notice thrown when someone is trying to execute a in some way auth protected logic
    error AvoMultisig__Unauthorized();

    /// @notice thrown when forwarder/relayer does not send enough gas as the user has defined.
    ///         this error should not be blamed on the user but rather on the relayer
    error AvoMultisig__InsufficientGasSent();
}

