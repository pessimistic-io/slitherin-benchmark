// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

/// @title Multicall
/// @notice Enables calling multiple methods in a single call to the contract
abstract contract Multicall {
    function _multicall(
        bytes[] calldata data
    ) internal returns (bytes[] memory results, uint[] memory gasEstimates) {
        results = new bytes[](data.length);
        gasEstimates = new uint[](data.length);

        unchecked {
            for (uint256 i = 0; i < data.length; ++i) {
                uint startGas = gasleft();
                (bool success, bytes memory result) = address(this)
                    .delegatecall(data[i]);

                if (!success) {
                    /// @solidity memory-safe-assembly
                    assembly {
                        let resultLength := mload(result)
                        revert(add(result, 0x20), resultLength)
                    }
                }

                results[i] = result;
                uint endGas = gasleft();
                gasEstimates[i] = startGas - endGas;
            }
        }
    }
}

