// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.9;

///Methods
enum TYPES {
    ADDRESS, // 0
    UINT256, // 1
    STRING, // 2
    BYTES32, // 3
    BOOL, // 4
    ADDRESS_ARRAY, // 5
    UINT_ARRAY // 6
}

struct MethodInfo {
    address interactionAddress;
    uint256 argcArray;
    InputArguments[] argv;
    uint256[] amountPositions;
    bool hasAmountsArray;
    address[] inTokens;
    address[] outTokens;
    string methodName;
}

struct InputArguments {
    TYPES argType; // type array to consider (ex 0 == addressArguments)
    uint8 argv; // Position in type array
}

struct CallInfo {
    address[] addressArguments;
    uint256[] uintArguments;
    string[] stringArguments;
    bool[] boolArguments;
    bytes32[] bytes32Arguments;
    address[][] addressArrayArguments;
    uint256[][] uintArrayArguments;
}

contract GenerateCallData {
    /// @notice Generates the calldata needed to complete a call
    ///     This function generates the calldata for a contract interaction
    /// @param method 4 bytes method selector
    /// @param args. The arguments passed to the method. This array should be created following ABI specifications.
    ///     As this router and directory version only relies on non-array parameters, we accept arguments in bytes32 slots
    function _generateCalldataFromBytes(bytes4 method, bytes32[] memory args) internal pure returns (bytes memory) {
        /// calculate the position where static elements start in the bytes array, 32 + 4 as the function selector is bytes4
        uint256 offset = 36;
        uint256 n = args.length;
        /// calculate the size of the bytes array and allocate the bytes array -- 2
        uint256 bSize = 4 + n * 32;
        bytes memory result = new bytes(bSize);
        /// concat the function selector of the method at the first position of the bytes array -- 3
        bytes4 selector = method;
        assembly {
            mstore(add(result, 32), selector)
        }
        /// loop through all the arguments of the method to add them to the calldata
        for (uint256 i; i < n; ++i) {
            /// get the position of the arg in the method and the input arg in bytes32
            bytes32 arg = args[i];
            assembly {
                mstore(add(result, offset), arg)
            }
            /// offset to write the next bytes32 arg during the next loop
            offset += 32;
        }
        return result;
    }
}

