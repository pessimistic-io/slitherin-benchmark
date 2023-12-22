pragma solidity ^0.8.17;

interface IPActionVePendleStatic {
    function increaseLockPositionStatic(
        address user,
        uint128 additionalAmountToLock,
        uint128 newExpiry
    ) external view returns (uint128 newVeBalance);
}

