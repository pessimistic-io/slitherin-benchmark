// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

import { IGuardsInternal } from "./IGuardsInternal.sol";

/// @title GuardsInternal
/// @dev contains common internal guard functions
abstract contract GuardsInternal is IGuardsInternal {
    /// @notice enforces that a value does not exceed the basis
    /// @param value value to check
    function _enforceBasis(uint32 value, uint32 basis) internal pure {
        if (value > basis) {
            revert BasisExceeded();
        }
    }
}

