// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

library Constants {
    /// @dev Used as a flag for identifying the transfer of ETH instead of a token
    address internal constant NATIVE_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    /// @dev Used as a impossible pool address
    address internal constant IMPOSSIBLE_POOL_ADDRESS = 0x0000000000000000000000000000000000000001;
    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
}

