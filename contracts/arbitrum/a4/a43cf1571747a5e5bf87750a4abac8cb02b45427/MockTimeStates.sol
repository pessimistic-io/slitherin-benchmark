// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.8.0;

import "./States.sol";

library MockTimeStates {
    bytes32 public constant STATES_SLOT = keccak256("states.storage");

    bytes32 public constant MOCK_TIME_SLOT = keccak256("mock.time.storage");

    struct PoolStates {
        address factory;
        address nfpManager;
        address veRam;
        address voter;
        address token0;
        address token1;
        uint24 fee;
        int24 tickSpacing;
        uint128 maxLiquidityPerTick;
        Slot0 slot0;
        mapping(uint256 => PeriodInfo) periods;
        uint256 lastPeriod;
        uint256 feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128;
        ProtocolFees protocolFees;
        uint128 liquidity;
        uint128 boostedLiquidity;
        mapping(int24 => TickInfo) _ticks;
        mapping(int16 => uint256) tickBitmap;
        mapping(bytes32 => PositionInfo) positions;
        mapping(uint256 => PeriodBoostInfo) boostInfos;
        mapping(bytes32 => uint256) attachedVeRamTokenId;
        Observation[65535] observations;
    }

    // Return state storage struct for reading and writing
    function getStorage()
        internal
        pure
        returns (PoolStates storage storageStruct)
    {
        bytes32 position = STATES_SLOT;
        assembly {
            storageStruct.slot := position
        }
    }

    /// @dev Returns the block timestamp truncated to 32 bits, i.e. mod 2**32. This method is overridden in tests.
    function _blockTimestamp() internal view returns (uint32) {
        uint32 _timestamp;
        bytes32 mockTimeSlot = MOCK_TIME_SLOT;

        assembly {
            _timestamp := sload(mockTimeSlot)
        }

        return _timestamp; // truncation is desired
    }
}

