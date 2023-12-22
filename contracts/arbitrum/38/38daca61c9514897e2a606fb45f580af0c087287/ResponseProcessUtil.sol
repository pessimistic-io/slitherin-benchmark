/*
 * SPDX-License-Identifier: Apache-2.0
 */
pragma solidity >=0.7.1;

import "./StringsUpgradeable.sol";

abstract contract ResponseProcessUtil {
    function getRevertMsg(bytes memory _returnData)
        internal
        pure
        returns (string memory)
    {
        // A string will be 4 bytes for the function selector + 32 bytes for string length +
        // 32 bytes for first part of string. Hence, if the length is less than 68, then
        // this is a panic.
        // Another way of doing this would be to look for the function selectors for revert:
        // "0x08c379a0" = keccak256("Error(string)"
        // or panic:
        // "0x4e487b71" = keccak256("Panic(uint256)"
        if (_returnData.length < 36) {
            return
                string(
                    abi.encodePacked(
                        "Revert for unknown error. Error length: ",
                        StringsUpgradeable.toString(_returnData.length)
                    )
                );
        }
        bool isPanic = _returnData.length < 68;

        assembly {
            // Remove the function selector / sighash.
            _returnData := add(_returnData, 0x04)
        }
        if (isPanic) {
            uint256 errorCode = abi.decode(_returnData, (uint256));
            return
                string(
                    abi.encodePacked("Panic: ", StringsUpgradeable.toString(errorCode))
                );
        }
        return abi.decode(_returnData, (string)); // All that remains is the revert string
    }
}

