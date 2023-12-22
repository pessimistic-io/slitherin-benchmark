// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Errors {
    error SuperTokenRequired();
    error NativeSuperTokenNotSupported();
    error ZeroAddress();
    error OperationNotAllowed();
    error SuperTokenNotUnderlying();
    error ERC20TransferRevert();
    error ERC20TransferFromRevert();
}
