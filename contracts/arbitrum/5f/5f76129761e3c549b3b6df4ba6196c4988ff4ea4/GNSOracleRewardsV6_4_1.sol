// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Initializable.sol";

import "./ChainUtils.sol";
import "./StorageInterfaceV5.sol";
import "./IGNSOracle.sol";

contract GNSOracleRewardsV6_4_1 is Initializable {
    // Constants
    uint private constant CHAIN_ID_POLY = 137;
    uint private constant CHAIN_ID_MUMBAI = 80001;
    uint private constant CHAIN_ID_ARBI = 42161;

    address private constant NFT_REWARDS_OLD_POLY = 0x8103C0665A544201BBF606d90845d1B2D8005F1c;
    address private constant NFT_REWARDS_OLD_MUMBAI = 0xf7Ac400b45Bdd2E098FaCA3642bE4d01071BC73B;
    address private constant NFT_REWARDS_OLD_ARBI = 0xde5750071CacA8db173FC6543D23d0BCACACFEC3;

    uint private constant MIN_TRIGGER_TIMEOUT = 1;

    // Addresses (constant)
    StorageInterfaceV5 public storageT;
    mapping(uint => address) public nftRewardsOldByChainId;

    // Params (adjustable)
    uint public triggerTimeout; // blocks
    address[] public oracles; // oracles rewarded

    // Custom data types
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
    mapping(address => uint) public pendingRewardsGns;
    mapping(address => mapping(uint => mapping(uint => mapping(StorageInterfaceV5.LimitOrder => uint))))
        public triggeredLimits;
    mapping(address => mapping(uint => mapping(uint => OpenLimitOrderType))) public openLimitOrderTypes;

    bool public stateCopied;

    // Events
    event OldLimitTypesCopied(address oldContract, uint start, uint end);
    event StateCopyDone();
    event TriggerTimeoutUpdated(uint value);
    event OraclesUpdated(uint oraclesCount);

    event TriggeredFirst(TriggeredLimitId id);
    event TriggerUnregistered(TriggeredLimitId id);
    event TriggerRewarded(TriggeredLimitId id, uint rewardGns, uint rewardGnsPerOracle, uint oraclesCount);
    event RewardsClaimed(address oracle, uint amountGns);
    event OpenLimitOrderTypeSet(address trader, uint pairIndex, uint index, OpenLimitOrderType value);

    function initialize(StorageInterfaceV5 _storageT, uint _triggerTimeout, uint _oraclesCount) external initializer {
        require(
            address(_storageT) != address(0) && _triggerTimeout >= MIN_TRIGGER_TIMEOUT && _oraclesCount > 0,
            "WRONG_PARAMS"
        );

        nftRewardsOldByChainId[CHAIN_ID_POLY] = NFT_REWARDS_OLD_POLY;
        nftRewardsOldByChainId[CHAIN_ID_MUMBAI] = NFT_REWARDS_OLD_MUMBAI;
        nftRewardsOldByChainId[CHAIN_ID_ARBI] = NFT_REWARDS_OLD_ARBI;

        storageT = _storageT;
        triggerTimeout = _triggerTimeout;

        _updateOracles(_oraclesCount);
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
        require(msg.sender == storageT.callbacks(), "CALLBACKS_ONLY");
        _;
    }

    // Copy limit order types from old nft rewards contract
    function copyOldLimitTypes(uint _start, uint _end) external onlyGov {
        require(!stateCopied, "COPY_DONE");
        require(_start <= _end, "START_AFTER_END");

        address oldAddress = nftRewardsOldByChainId[block.chainid];
        require(oldAddress != address(0), "UNKNOWN_CHAIN");

        StorageInterfaceV5.OpenLimitOrder[] memory openLimitOrders = IStateCopyUtils(address(storageT))
            .getOpenLimitOrders();

        require(_start < openLimitOrders.length, "START_TOO_BIG");

        if (_end >= openLimitOrders.length) {
            _end = openLimitOrders.length - 1;
        }

        NftRewardsInterfaceV6_3_1 old = NftRewardsInterfaceV6_3_1(oldAddress);

        for (uint i = _start; i <= _end; ) {
            StorageInterfaceV5.OpenLimitOrder memory o = openLimitOrders[i];

            openLimitOrderTypes[o.trader][o.pairIndex][o.index] = OpenLimitOrderType(
                uint(old.openLimitOrderTypes(o.trader, o.pairIndex, o.index))
            );

            unchecked {
                ++i;
            }
        }

        emit OldLimitTypesCopied(oldAddress, _start, _end);
    }

    function setStateCopyAsDone() external onlyGov {
        stateCopied = true;

        emit StateCopyDone();
    }

    // Manage params
    function updateTriggerTimeout(uint _triggerTimeout) external onlyGov {
        require(_triggerTimeout >= MIN_TRIGGER_TIMEOUT, "BELOW_MIN");

        triggerTimeout = _triggerTimeout;

        emit TriggerTimeoutUpdated(_triggerTimeout);
    }

    function _updateOracles(uint _oraclesCount) private {
        require(_oraclesCount > 0, "VALUE_ZERO");

        delete oracles;

        for (uint i; i < _oraclesCount; ) {
            oracles.push(storageT.priceAggregator().nodes(i));

            unchecked {
                ++i;
            }
        }

        emit OraclesUpdated(_oraclesCount);
    }

    function updateOracles(uint _oraclesCount) external onlyGov {
        _updateOracles(_oraclesCount);
    }

    // Triggers
    function storeTrigger(TriggeredLimitId calldata _id) external onlyTrading {
        triggeredLimits[_id.trader][_id.pairIndex][_id.index][_id.order] = ChainUtils.getBlockNumber();

        emit TriggeredFirst(_id);
    }

    function unregisterTrigger(TriggeredLimitId calldata _id) external onlyCallbacks {
        delete triggeredLimits[_id.trader][_id.pairIndex][_id.index][_id.order];

        emit TriggerUnregistered(_id);
    }

    // Distribute oracle rewards
    function distributeOracleReward(TriggeredLimitId calldata _id, uint _reward) external onlyCallbacks {
        require(triggered(_id), "NOT_TRIGGERED");

        uint oraclesCount = oracles.length;
        uint rewardPerOracle = _reward / oraclesCount;

        for (uint i; i < oraclesCount; ) {
            pendingRewardsGns[oracles[i]] += rewardPerOracle;

            unchecked {
                ++i;
            }
        }

        storageT.handleTokens(address(this), _reward, true);

        emit TriggerRewarded(_id, _reward, rewardPerOracle, oraclesCount);
    }

    // Claim oracle rewards
    function claimRewards(address _oracle) external {
        IGNSOracle _o = IGNSOracle(_oracle);

        // msg.sender must either be the oracle owner or an authorized fulfiller
        require(_o.owner() == msg.sender || _o.getAuthorizationStatus(msg.sender), "NOT_AUTHORIZED");

        uint amountGns = pendingRewardsGns[_oracle];

        pendingRewardsGns[_oracle] = 0;
        storageT.token().transfer(msg.sender, amountGns);

        emit RewardsClaimed(_oracle, amountGns);
    }

    // Manage open limit order types
    function setOpenLimitOrderType(
        address _trader,
        uint _pairIndex,
        uint _index,
        OpenLimitOrderType _type
    ) external onlyTrading {
        openLimitOrderTypes[_trader][_pairIndex][_index] = _type;

        emit OpenLimitOrderTypeSet(_trader, _pairIndex, _index, _type);
    }

    // Getters
    function triggered(TriggeredLimitId calldata _id) public view returns (bool) {
        return triggeredLimits[_id.trader][_id.pairIndex][_id.index][_id.order] > 0;
    }

    function timedOut(TriggeredLimitId calldata _id) external view returns (bool) {
        uint triggerBlock = triggeredLimits[_id.trader][_id.pairIndex][_id.index][_id.order];

        return triggerBlock > 0 && ChainUtils.getBlockNumber() - triggerBlock >= triggerTimeout;
    }

    function getOracles() external view returns (address[] memory) {
        return oracles;
    }
}

