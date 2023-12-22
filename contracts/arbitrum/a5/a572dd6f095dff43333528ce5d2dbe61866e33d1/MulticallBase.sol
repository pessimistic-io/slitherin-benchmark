// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @title MulticallBase
/// @dev Contract that provides a base functionality for making multiple calls in a single transaction.
contract MulticallBase {
    /// @notice Executes multiple calls in a single transaction.
    /// @dev Iterates through an array of call data and executes each call.
    /// If any call fails, the function reverts with the original error message.
    /// @param data An array of call data to be executed.
    function _multicall(bytes[] calldata data) internal {
        uint256 length = data.length;

        bool success;

        for (uint256 i; i < length; ) {
            (success, ) = address(this).call(data[i]);

            // If unsuccess occured -> revert with original error message
            if (!success) {
                assembly ("memory-safe") {
                    returndatacopy(0, 0, returndatasize())
                    revert(0, returndatasize())
                }
            }

            unchecked {
                // increment loop counter
                ++i;
            }
        }
    }
}

