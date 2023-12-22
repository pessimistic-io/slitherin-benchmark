// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

/**
 * `Quota` is a token allowance that a payer grants to a controller. The controller can pull token from the payer
 * address periodically according to the schedule defined in the quota.
 *
 * To protect payers, if the controller misses a charge cycle, the quota will be automatically cancelled.
 * Also, payers can revoke their approved quotas at any time.
 */
struct Quota {
    // payer info
    address payer; //           slot 0
    uint96 payerNonce;
    // token amount
    address token; //           slot 1
    uint160 amount; //          slot 2
    // charge schedule
    uint40 startTime;
    uint40 endTime;
    uint40 interval; //         slot 3
    uint40 chargeWindow;
    // controller info
    address controller;
    bytes32 controllerRefId; // slot 4
}

struct QuotaState {
    bool validated;
    bool cancelled; // by payer
    uint40 cycleStartTime;
    uint160 cycleAmountUsed;
    uint24 chargeCount;
}

enum QuotaStatus {
    NotStarted,
    PendingFirstCharge,
    Active,
    PendingNextCharge,
    Cancelled
}

library QuotaLib {
    bytes32 internal constant _QUOTA_TYPEHASH = keccak256(
        "Quota(address payer,uint96 payerNonce,address token,uint160 amount,uint40 startTime,uint40 endTime,uint40 interval,uint40 chargeWindow,address controller,bytes32 controllerRefId)"
    );

    function hash(Quota memory quota) internal pure returns (bytes32 quotaHash) {
        return keccak256(abi.encode(_QUOTA_TYPEHASH, quota));
    }

    /// @notice Calculate the start time of the quota's latest possible cycle
    /// @dev Assumed now >= quota.startTime, or else it reverts. Also, end time is not checked here.
    function latestCycleStartTime(Quota memory quota) internal view returns (uint40) {
        return quota.startTime + (((uint40(block.timestamp) - quota.startTime) / quota.interval) * quota.interval);
    }

    /// @notice Check whether the quota's latest cycle has been charged once
    function didChargeLatestCycle(Quota memory quota, QuotaState memory state) internal view returns (bool) {
        return state.chargeCount != 0 && uint256(state.cycleStartTime) + quota.interval > block.timestamp;
    }

    /// @notice Check whether the quota has missed any billing cycle
    function didMissCycle(Quota memory quota, QuotaState memory state) internal view returns (bool) {
        return state.chargeCount == 0
            ? uint256(quota.startTime) + quota.chargeWindow <= block.timestamp
            : uint256(state.cycleStartTime) + quota.interval + quota.chargeWindow <= block.timestamp;
    }

    /// @notice Calcuate the end time of the quota's current cycle, i.e. the cycle that the last charge happened in.
    function currentCycleEndTime(Quota memory quota, QuotaState memory state) internal pure returns (uint40) {
        uint256 endTime = uint256(state.cycleStartTime) + quota.interval;
        return endTime > type(uint40).max ? type(uint40).max : uint40(endTime); // truncate to uint40
    }
}

