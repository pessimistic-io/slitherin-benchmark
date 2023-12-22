// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { SafeCast } from "./SafeCast.sol";

/// @title Solarray
/// @author Umami DAO
/// @notice Array functions
library Solarray {
    function uint256s(uint256 a, uint256 b, uint256 c, uint256 d) internal pure returns (uint256[4] memory) {
        uint256[4] memory arr;
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
        arr[3] = d;
        return arr;
    }

    function uint256s(uint256 a, uint256 b, uint256 c, uint256 d, uint256 e)
        internal
        pure
        returns (uint256[5] memory)
    {
        uint256[5] memory arr;
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
        arr[3] = d;
        arr[4] = e;
        return arr;
    }

    function int256s(int256 a, int256 b, int256 c, int256 d) internal pure returns (int256[4] memory) {
        int256[4] memory arr;
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
        arr[3] = d;
        return arr;
    }

    function int256s(int256 a, int256 b, int256 c, int256 d, int256 e) internal pure returns (int256[5] memory) {
        int256[5] memory arr;
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
        arr[3] = d;
        arr[4] = e;
        return arr;
    }

    function addresss(address a, address b, address c, address d, address e)
        internal
        pure
        returns (address[5] memory)
    {
        address[5] memory arr;
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
        arr[3] = d;
        arr[4] = e;
        return arr;
    }

    function intToUintArray(int256[5] memory _array) internal pure returns (uint256[5] memory uintArray) {
        require(
            _array[0] > 0 && _array[1] > 0 && _array[2] > 0 && _array[3] > 0 && _array[4] > 0,
            "Solarray: intToUintArray: negative value"
        );
        uintArray = [uint256(_array[0]), uint256(_array[1]), uint256(_array[2]), uint256(_array[3]), uint256(_array[4])];
    }

    function arraySum(int256[4] memory _array) internal pure returns (int256 sum) {
        for (uint256 i = 0; i < _array.length; i++) {
            sum += _array[i];
        }
    }

    function arraySum(int256[5] memory _array) internal pure returns (int256 sum) {
        for (uint256 i = 0; i < _array.length; i++) {
            sum += _array[i];
        }
    }

    function arraySum(uint256[5] memory _array) internal pure returns (uint256 sum) {
        for (uint256 i = 0; i < _array.length; i++) {
            sum += _array[i];
        }
    }

    function arraySumAbsolute(int256[5] memory _array) internal pure returns (uint256 sum) {
        for (uint256 i = 0; i < _array.length; i++) {
            sum += _array[i] > 0 ? uint256(_array[i]) : uint256(-_array[i]);
        }
    }

    function arrayDifference(uint256[5] memory _base, int256[5] memory _difference)
        internal
        pure
        returns (int256[5] memory result)
    {
        for (uint256 i = 0; i < 5; i++) {
            result[i] = SafeCast.toInt256(_base[i]) + _difference[i];
        }
    }

    function scaleArray(uint256[4] memory _array, uint256 _scale) internal pure returns (uint256[4] memory _retArray) {
        for (uint256 i = 0; i < _array.length; i++) {
            _retArray[i] = _array[i] * _scale / 1e18;
        }
    }

    function scaleArray(uint256[5] memory _array, uint256 _scale) internal pure returns (uint256[5] memory _retArray) {
        for (uint256 i = 0; i < _array.length; i++) {
            _retArray[i] = _array[i] * _scale / 1e18;
        }
    }

    function sumColumns(int256[5][4] memory _array) internal pure returns (int256[4] memory _retArray) {
        for (uint256 i = 0; i < _array.length; i++) {
            for (uint256 j = 0; j < 5; j++) {
                _retArray[i] += _array[j][i];
            }
        }
    }

    function sumColumns(int256[5][5] memory _array) internal pure returns (int256[5] memory _retArray) {
        for (uint256 i = 0; i < _array.length; i++) {
            for (uint256 j = 0; j < _array.length; j++) {
                _retArray[i] += _array[j][i];
            }
        }
    }

    function int5FixedToDynamic(int256[5] memory _arr) public view returns (int256[] memory _retArr) {
        bytes memory _ret = fixedToDynamicArray(abi.encode(_arr), 5);
        /// @solidity memory-safe-assembly
        assembly {
            _retArr := _ret // point to the array
        }
    }

    function uint5FixedToDynamic(uint256[5] memory _arr) internal view returns (uint256[] memory _retArr) {
        bytes memory _ret = fixedToDynamicArray(abi.encode(_arr), 5);
        /// @solidity memory-safe-assembly
        assembly {
            _retArr := _ret // point to the array
        }
    }

    function fixedToDynamicArray(bytes memory _arr, uint256 _fixedSize) public view returns (bytes memory _retArray) {
        (bool success, bytes memory data) = address(0x04).staticcall(_arr);
        require(success, "identity precompile failed");
        /// @solidity memory-safe-assembly
        assembly {
            _retArray := data // point to the copied data
            mstore(_retArray, _fixedSize) // store array length
        }
    }
}

