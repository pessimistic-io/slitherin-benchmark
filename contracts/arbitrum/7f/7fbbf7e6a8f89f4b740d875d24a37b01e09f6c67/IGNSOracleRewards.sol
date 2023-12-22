// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IGNSTradingStorage.sol";

/**
 * @custom:version 6.4.1
 */
interface IGNSOracleRewards {
    struct TriggeredLimitId {
        address trader;
        uint256 pairIndex;
        uint256 index;
        IGNSTradingStorage.LimitOrder order;
    }

    enum OpenLimitOrderType {
        LEGACY,
        REVERSAL,
        MOMENTUM
    }

    function storeTrigger(TriggeredLimitId calldata) external;

    function unregisterTrigger(TriggeredLimitId calldata) external;

    function distributeOracleReward(TriggeredLimitId calldata, uint256) external;

    function openLimitOrderTypes(address, uint256, uint256) external view returns (OpenLimitOrderType);

    function setOpenLimitOrderType(address, uint256, uint256, OpenLimitOrderType) external;

    function triggered(TriggeredLimitId calldata) external view returns (bool);

    function timedOut(TriggeredLimitId calldata) external view returns (bool);

    event OldLimitTypesCopied(address oldContract, uint256 start, uint256 end);
    event StateCopyDone();
    event TriggerTimeoutUpdated(uint256 value);
    event OraclesUpdated(uint256 oraclesCount);

    event TriggeredFirst(TriggeredLimitId id);
    event TriggerUnregistered(TriggeredLimitId id);
    event TriggerRewarded(TriggeredLimitId id, uint256 rewardGns, uint256 rewardGnsPerOracle, uint256 oraclesCount);
    event RewardsClaimed(address oracle, uint256 amountGns);
    event OpenLimitOrderTypeSet(address trader, uint256 pairIndex, uint256 index, OpenLimitOrderType value);
}

