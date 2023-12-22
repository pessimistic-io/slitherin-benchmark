// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

/// @title Handles errors using custom errors
/// @author Pino Development Team
contract Errors {
    error ProxyError(uint256 errCode);

    /// @notice Handles custom error codes
    /// @param _condition The condition, if it's false then execution is reverted
    /// @param _code Custom code, listed in Errors.sol
    function _require(bool _condition, uint256 _code) internal pure {
        if (!_condition) {
            revert ProxyError(_code);
        }
    }
}

