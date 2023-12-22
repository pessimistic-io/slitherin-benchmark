// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

/// @title IGuardsInternal
/// @dev GuardsInternal interface holding all errors related to common guards
interface IGuardsInternal {
    /// @notice thrown when attempting to set a value larger than basis
    error BasisExceeded();
}

