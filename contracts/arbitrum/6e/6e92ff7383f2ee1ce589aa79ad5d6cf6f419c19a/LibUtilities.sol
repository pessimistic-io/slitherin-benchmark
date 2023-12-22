// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { PausableStorage } from "./PausableStorage.sol";
import { StringsUpgradeable } from "./StringsUpgradeable.sol";
import { LibMeta } from "./LibMeta.sol";

library LibUtilities {
    event Paused(address account);
    event Unpaused(address account);

    error ArrayLengthMismatch(uint256 len1, uint256 len2);

    error IsPaused();
    error NotPaused();

    // =============================================================
    //                      Array Helpers
    // =============================================================

    function requireArrayLengthMatch(uint256 _length1, uint256 _length2) internal pure {
        if (_length1 != _length2) {
            revert ArrayLengthMismatch(_length1, _length2);
        }
    }

    function asSingletonArray(uint256 _item) internal pure returns (uint256[] memory array_) {
        array_ = new uint256[](1);
        array_[0] = _item;
    }

    function asSingletonArray(string memory _item) internal pure returns (string[] memory array_) {
        array_ = new string[](1);
        array_[0] = _item;
    }

    // =============================================================
    //                     Misc Functions
    // =============================================================

    function compareStrings(string memory _a, string memory _b) public pure returns (bool) {
        return (keccak256(abi.encodePacked((_a))) == keccak256(abi.encodePacked((_b))));
    }

    function setPause(bool _paused) internal {
        PausableStorage.layout()._paused = _paused;
        if (_paused) {
            emit Paused(LibMeta._msgSender());
        } else {
            emit Unpaused(LibMeta._msgSender());
        }
    }

    function paused() internal view returns (bool) {
        return PausableStorage.layout()._paused;
    }

    function requirePaused() internal view {
        if (!paused()) {
            revert NotPaused();
        }
    }

    function requireNotPaused() internal view {
        if (paused()) {
            revert IsPaused();
        }
    }

    function toString(uint256 _value) internal pure returns (string memory) {
        return StringsUpgradeable.toString(_value);
    }

    /**
     * @notice This function takes the first 4 MSB of the given bytes32 and converts them to _a bytes4
     * @dev This function is useful for grabbing function selectors from calldata
     * @param _inBytes The bytes to convert to bytes4
     */
    function convertBytesToBytes4(bytes memory _inBytes) internal pure returns (bytes4 outBytes4_) {
        if (_inBytes.length == 0) {
            return 0x0;
        }

        assembly {
            outBytes4_ := mload(add(_inBytes, 32))
        }
    }
}

