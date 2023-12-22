// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

struct BatchInfo {
    uint128 rewardTokens;
    uint256 totalValue;
    uint128 totalWeight;
    uint64 startTime;
    uint64 endTime;
    uint64 finalizedTime;
    bool leaderUpdated;
}

struct LeaderInfo {
    uint128 weight;
    uint128 claimed;
    uint256 totalPoint;
    uint8 index;
}

struct LeaderInfoView {
    address trader;
    uint128 rewardTokens;
    uint128 claimed;
    uint256 totalPoint;
    uint8 index;
}

struct ContestResult {
    address trader;
    uint8 index;
    uint256 totalPoint;
}

interface ILadder {
    function batchDuration() external returns (uint64);

    /**
     * @notice record trading point for trader
     * @param _user address of trader
     * @param _value fee collected in this trade
     */
    function record(address _user, uint256 _value) external;

    /**
     * @notice start a new batch and close current batch. Waiting for leaders to be set
     */
    function nextBatch() external;
}

