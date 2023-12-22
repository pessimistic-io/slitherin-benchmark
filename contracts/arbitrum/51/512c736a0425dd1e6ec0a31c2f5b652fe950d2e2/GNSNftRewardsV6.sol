// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IStorageInterfaceV5.sol";

abstract contract GNSNftRewardsV6 {
    // Contracts (constant)
    StorageInterfaceV5 public storageT;

    // Params (constant)
    uint constant ROUND_LENGTH = 50;
    uint constant MIN_TRIGGER_TIMEOUT = 1;
    uint constant MIN_SAME_BLOCK_LIMIT = 5;

    // Params (adjustable)
    uint public triggerTimeout; // blocks
    uint public sameBlockLimit; // bots

    uint public firstP; // %
    uint public sameBlockP; // %
    uint public poolP; // %

    // Custom data types
    struct TriggeredLimit {
        address first;
        address[] sameBlock;
        uint block;
    }
    struct TriggeredLimitId {
        address trader;
        uint pairIndex;
        uint index;
        StorageInterfaceV5.LimitOrder order;
    }

    enum OpenLimitOrderType {
        LEGACY,
        REVERSAL,
        MOMENTUM
    }

    // State
    uint public currentOrder; // current order in round
    uint public currentRound; // current round (1 round = 50 orders)

    mapping(uint => uint) public roundTokens; // total token rewards for a round
    mapping(address => mapping(uint => uint)) public roundOrdersToClaim; // orders to claim from a round (out of 50)

    mapping(address => uint) public tokensToClaim; // rewards other than pool (first & same block)

    mapping(address => mapping(uint => mapping(uint => mapping(StorageInterfaceV5.LimitOrder => TriggeredLimit))))
        public triggeredLimits; // limits being triggered

    mapping(address => mapping(uint => mapping(uint => OpenLimitOrderType))) public openLimitOrderTypes;

    // Statistics
    mapping(address => uint) public tokensClaimed; // 1e18
    uint public tokensClaimedTotal; // 1e18

    // Events
    event NumberUpdated(string name, uint value);
    event PercentagesUpdated(uint firstP, uint sameBlockP, uint poolP);

    event TriggeredFirst(TriggeredLimitId id, address bot);
    event TriggeredSameBlock(TriggeredLimitId id, address bot);
    event TriggerUnregistered(TriggeredLimitId id);
    event TriggerRewarded(TriggeredLimitId id, address first, uint sameBlockCount, uint reward);

    event PoolTokensClaimed(address bot, uint fromRound, uint toRound, uint tokens);
    event TokensClaimed(address bot, uint tokens);

    function initialize(
        StorageInterfaceV5 _storageT,
        uint _triggerTimeout,
        uint _sameBlockLimit,
        uint _firstP,
        uint _sameBlockP,
        uint _poolP
    ) external virtual;

    // Manage params
    function updateTriggerTimeout(uint _triggerTimeout) external virtual;

    function updateSameBlockLimit(uint _sameBlockLimit) external virtual;

    function updatePercentages(uint _firstP, uint _sameBlockP, uint _poolP) external virtual;

    // Triggers
    function storeFirstToTrigger(TriggeredLimitId calldata _id, address _bot) external virtual;

    function storeTriggerSameBlock(TriggeredLimitId calldata _id, address _bot) external virtual;

    function unregisterTrigger(TriggeredLimitId calldata _id) external virtual;

    // Distribute rewards
    function distributeNftReward(TriggeredLimitId calldata _id, uint _reward) external virtual;

    // Claim rewards
    function claimPoolTokens(uint _fromRound, uint _toRound) external virtual;

    function claimTokens() external virtual;

    // Manage open limit order types
    function setOpenLimitOrderType(
        address _trader,
        uint _pairIndex,
        uint _index,
        OpenLimitOrderType _type
    ) external virtual;

    // Getters
    function triggered(TriggeredLimitId calldata _id) external view virtual returns (bool);

    function timedOut(TriggeredLimitId calldata _id) external view virtual returns (bool);

    function sameBlockTriggers(TriggeredLimitId calldata _id) external view virtual returns (address[] memory);
}

