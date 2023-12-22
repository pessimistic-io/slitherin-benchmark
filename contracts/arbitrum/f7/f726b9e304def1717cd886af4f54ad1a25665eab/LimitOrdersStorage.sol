pragma solidity 0.8.15;
// SPDX-License-Identifier: MIT

import "./TokenInterface.sol";
import "./AggregatorInterface.sol";
import "./PoolInterface.sol";
import "./PausableInterface.sol";
import "./PairInfoInterface.sol";
import "./NarwhalReferralInterface.sol";
import "./LimitOrdersInterface.sol";

contract LimitOrdersStorage {
    // Contracts (constant)
    StorageInterface public immutable storageT;

    // Params (adjustable)
    uint public triggerTimeout = 5; // blocks
    uint public sameBlockLimit = 10; // bots

    uint public firstP = 40; // %
    uint public sameBlockP = 20; // %
    uint public poolP = 40; // %

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
        StorageInterface.LimitOrder order;
    }

    enum OpenLimitOrderType {
        LEGACY,
        REVERSAL,
        MOMENTUM
    }

    mapping(address => mapping(uint => mapping(uint => mapping(StorageInterface.LimitOrder => TriggeredLimit))))
        public triggeredLimits; // limits being triggered

    mapping(address => mapping(uint => mapping(uint => OpenLimitOrderType)))
        public openLimitOrderTypes;
    
    mapping(address => bool) public allowedToInteract;


    // Events
    event NumberUpdated(string name, uint value);
    event PercentagesUpdated(uint firstP, uint sameBlockP, uint poolP);

    event TriggeredFirst(TriggeredLimitId id, address bot);
    event TriggeredSameBlock(TriggeredLimitId id, address bot);
    event TriggerUnregistered(TriggeredLimitId id);
    event TriggerRewarded(
        TriggeredLimitId id,
        address first,
        uint sameBlockCount,
        uint reward
    );

    constructor(StorageInterface _storageT) {
        require(address(_storageT) != address(0), "ZERO_ADDRESS");
        storageT = _storageT;
    }

    // Modifiers
    modifier onlyGov() {
        require(msg.sender == storageT.gov(), "GOV_ONLY");
        _;
    }
    modifier onlyTrading() {
        require(msg.sender == storageT.trading(), "TRADING_ONLY");
        _;
    }
    modifier onlyCallbacks() {
        require(msg.sender == storageT.callbacks() || allowedToInteract[msg.sender], "NOT_ALLOWED");
        _;
    }

    function setAllowedToInteract(address _sender, bool _status) public onlyGov {
        allowedToInteract[_sender] = _status;
    }

    // Manage params
    function updateTriggerTimeout(uint _triggerTimeout) external onlyGov {
        require(_triggerTimeout >= 5, "LESS_THAN_5");
        triggerTimeout = _triggerTimeout;
        emit NumberUpdated("triggerTimeout", _triggerTimeout);
    }

    function updateSameBlockLimit(uint _sameBlockLimit) external onlyGov {
        require(_sameBlockLimit >= 5, "LESS_THAN_5");
        sameBlockLimit = _sameBlockLimit;
        emit NumberUpdated("sameBlockLimit", _sameBlockLimit);
    }

    function updatePercentages(
        uint _firstP,
        uint _sameBlockP,
        uint _poolP
    ) external onlyGov {
        require(_firstP + _sameBlockP + _poolP == 100, "SUM_NOT_100");

        firstP = _firstP;
        sameBlockP = _sameBlockP;
        poolP = _poolP;

        emit PercentagesUpdated(_firstP, _sameBlockP, _poolP);
    }

    // Triggers
    function storeFirstToTrigger(
        TriggeredLimitId calldata _id,
        address _bot
    ) external onlyTrading {
        TriggeredLimit storage t = triggeredLimits[_id.trader][_id.pairIndex][
            _id.index
        ][_id.order];

        t.first = _bot;
        delete t.sameBlock;
        t.block = block.number;

        emit TriggeredFirst(_id, _bot);
    }

    function storeTriggerSameBlock(
        TriggeredLimitId calldata _id,
        address _bot
    ) external onlyTrading {
        TriggeredLimit storage t = triggeredLimits[_id.trader][_id.pairIndex][
            _id.index
        ][_id.order];

        require(t.block == block.number, "TOO_LATE");
        require(t.sameBlock.length < sameBlockLimit, "SAME_BLOCK_LIMIT");

        t.sameBlock.push(_bot);

        emit TriggeredSameBlock(_id, _bot);
    }

    function unregisterTrigger(
        TriggeredLimitId calldata _id
    ) external onlyCallbacks {
        delete triggeredLimits[_id.trader][_id.pairIndex][_id.index][_id.order];
        emit TriggerUnregistered(_id);
    }

    // Manage open limit order types
    function setOpenLimitOrderType(
        address _trader,
        uint _pairIndex,
        uint _index,
        OpenLimitOrderType _type
    ) external onlyTrading {
        openLimitOrderTypes[_trader][_pairIndex][_index] = _type;
    }

    // Getters
    function triggered(
        TriggeredLimitId calldata _id
    ) external view returns (bool) {
        TriggeredLimit memory t = triggeredLimits[_id.trader][_id.pairIndex][
            _id.index
        ][_id.order];
        return t.block > 0;
    }

    function timedOut(
        TriggeredLimitId calldata _id
    ) external view returns (bool) {
        TriggeredLimit memory t = triggeredLimits[_id.trader][_id.pairIndex][
            _id.index
        ][_id.order];
        return t.block > 0 && block.number - t.block >= triggerTimeout;
    }

    function sameBlockTriggers(
        TriggeredLimitId calldata _id
    ) external view returns (address[] memory) {
        return
            triggeredLimits[_id.trader][_id.pairIndex][_id.index][_id.order]
                .sameBlock;
    }
}

