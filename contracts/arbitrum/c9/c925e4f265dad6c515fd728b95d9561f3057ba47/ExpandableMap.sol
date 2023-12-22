// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/** This contract implements world expansion and boundary checks for new pixels
 */
contract ExpandableMap {
    uint32 private _unlockedMapSize;
    uint16 private immutable _mapUnlockStep;
    uint8 private immutable _mapUnlockPercentage;
    uint64 private _paintedPixels = 0;

    event WorldExpanded(uint32 size);

    constructor(
        uint32 unlockedMapSize,
        uint16 mapUnlockStep,
        uint8 mapUnlockPercentage
    ) {
        _unlockedMapSize = unlockedMapSize;
        _mapUnlockStep = mapUnlockStep;
        _mapUnlockPercentage = mapUnlockPercentage;
    }

    function isUnlocked(
        uint16 y,
        uint16 x
    ) public view returns (bool unlocked) {
        uint256 upperBound = 2 ** 15 + _unlockedMapSize / 2;
        uint256 lowerBound = 2 ** 15 - _unlockedMapSize / 2;
        return (y < upperBound &&
            y >= lowerBound &&
            x < upperBound &&
            x >= lowerBound);
    }

    // Expand the unlocked area if _mapUnlockPercentage of unlocked pixels are
    // already painted.
    function expandIfNeeded() private {
        uint256 currentSize = uint256(_unlockedMapSize) ** 2;
        if (
            uint256(_paintedPixels) >=
            (currentSize * _mapUnlockPercentage) / 100
        ) {
            unchecked {
                bool noOverflow = _unlockedMapSize + _mapUnlockStep >
                    _unlockedMapSize;
                if (noOverflow) {
                    _unlockedMapSize += _mapUnlockStep;
                    emit WorldExpanded(_unlockedMapSize);
                }
            }
        }
    }

    // Add a number of pixels to the counter
    function paintNewPixels(uint32 newPixelCount) internal {
        unchecked {
            if (_paintedPixels + newPixelCount <= type(uint32).max) {
                _paintedPixels += newPixelCount;
                expandIfNeeded();
            }
        }
    }

    function getUnlockedWorldSize() public view returns (uint32) {
        return _unlockedMapSize;
    }
}

