pragma solidity >=0.8.0;

library SafeCast {
    error Overflow();

    function toUint256(int256 value) internal pure returns (uint256) {
        if (value < 0) {
            revert Overflow();
        }
        return uint256(value);
    }

    function toInt256(uint256 value) internal pure returns (int256) {
        // Note: Unsafe cast below is okay because `type(int256).max` is guaranteed to be positive
        if (value > uint256(type(int256).max)) {
            revert Overflow();
        }
        return int256(value);
    }
}

