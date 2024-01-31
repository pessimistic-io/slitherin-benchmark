// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.11;

import "./ISwapData.sol";

/// @notice Strategy total underlying slippage, to verify validity of the strategy state
struct StratUnderlyingSlippage {
    uint256 min;
    uint256 max;
}

/// @notice Containig information if and how to swap strategy rewards at the DHW
/// @dev Passed in by the do-hard-worker
struct RewardSlippages {
    bool doClaim;
    SwapData[] swapData;
}

/// @notice Calldata when executing reallocatin DHW
/// @notice Used in the withdraw part of the reallocation DHW
struct ReallocationWithdrawData {
    uint256[][] reallocationTable;
    StratUnderlyingSlippage[] priceSlippages;
    RewardSlippages[] rewardSlippages;
    uint256[] stratIndexes;
    uint256[][] slippages;
}

/// @notice Calldata when executing reallocatin DHW
/// @notice Used in the deposit part of the reallocation DHW
struct ReallocationData {
    uint256[] stratIndexes;
    uint256[][] slippages;
}

interface ISpoolHelper {
    /* ========== FUNCTIONS ========== */
    function batchDoHardWorkReallocation(
        ReallocationWithdrawData memory withdrawData,
        ReallocationData memory depositData,
        address[] memory allStrategies,
        bool isOneTransaction
    ) external;

    function isDoHardWorker(address account) external view returns (bool);
}

