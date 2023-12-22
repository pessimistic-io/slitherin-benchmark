// SPDX-License-Identifier: MIT
import "./StorageInterfaceV5.sol";
pragma solidity 0.8.10;

contract MTTPairStorage {
    // Contracts (constant)
    StorageInterfaceV5 immutable storageT;

    // Params (constant)
    uint256 constant MIN_LEVERAGE = 2;
    uint256 constant MAX_LEVERAGE = 1000;

    // Custom data types
    enum FeedCalculation {
        DEFAULT,
        INVERT,
        COMBINE,
        UNDEFINED
    }
    struct Feed {
        address feed1;
        address feed2;
        FeedCalculation feedCalculation;
        uint256 maxDeviationP;
    } // PRECISION (%)

    struct Pair {
        string from;
        string to;
        Feed feed;
        uint256 spreadP; // PRECISION
        uint256 groupIndex;
        uint256 feeIndex;
    }
    struct Group {
        string name;
        bytes32 job;
        uint256 minLeverage;
        uint256 maxLeverage;
        uint256 maxCollateralP; // % (of DAI vault current balance)
    }
    struct Fee {
        string name;
        uint256 openFeeP; // PRECISION (% of leveraged pos)
        uint256 closeFeeP; // PRECISION (% of leveraged pos)
        uint256 oracleFeeP; // PRECISION (% of leveraged pos)
        uint256 nftLimitOrderFeeP; // PRECISION (% of leveraged pos)
        uint256 referralFeeP; // PRECISION (% of leveraged pos)
        uint256 minLevPosDai; // 1e18 (collateral x leverage, useful for min fee)
    }

    // State
    uint256 public currentOrderId;

    uint256 public pairsCount;
    uint256 public groupsCount;
    uint256 public feesCount;

    mapping(uint256 => Pair) public pairs;
    mapping(uint256 => Group) public groups;
    mapping(uint256 => Fee) public fees;

    mapping(string => mapping(string => bool)) public isPairListed;

    mapping(uint256 => uint256[2]) public groupsCollaterals; // (long, short)

    // Events
    event PairAdded(uint256 index, string from, string to);
    event PairUpdated(uint256 index);

    event GroupAdded(uint256 index, string name);
    event GroupUpdated(uint256 index);

    event FeeAdded(uint256 index, string name);
    event FeeUpdated(uint256 index);

    constructor(uint256 _currentOrderId, StorageInterfaceV5 _storageT) {
        require(_currentOrderId > 0, "ORDER_ID_0");
        currentOrderId = _currentOrderId;
        storageT = _storageT;
    }

    // Modifiers
    modifier onlyGov() {
        require(msg.sender == storageT.gov(), "GOV_ONLY");
        _;
    }

    modifier groupListed(uint256 _groupIndex) {
        require(groups[_groupIndex].minLeverage > 0, "GROUP_NOT_LISTED");
        _;
    }
    modifier feeListed(uint256 _feeIndex) {
        require(fees[_feeIndex].openFeeP > 0, "FEE_NOT_LISTED");
        _;
    }

    modifier feedOk(Feed calldata _feed) {
        require(
            _feed.maxDeviationP > 0 && _feed.feed1 != address(0),
            "WRONG_FEED"
        );
        require(
            _feed.feedCalculation != FeedCalculation.COMBINE ||
                _feed.feed2 != address(0),
            "FEED_2_MISSING"
        );
        _;
    }
    modifier groupOk(Group calldata _group) {
        require(_group.job != bytes32(0), "JOB_EMPTY");
        require(
            _group.minLeverage >= MIN_LEVERAGE &&
                _group.maxLeverage <= MAX_LEVERAGE &&
                _group.minLeverage < _group.maxLeverage,
            "WRONG_LEVERAGES"
        );
        _;
    }
    modifier feeOk(Fee calldata _fee) {
        require(
            _fee.openFeeP > 0 &&
                _fee.closeFeeP > 0 &&
                _fee.oracleFeeP > 0 &&
                _fee.nftLimitOrderFeeP > 0 &&
                _fee.referralFeeP > 0 &&
                _fee.minLevPosDai > 0,
            "WRONG_FEES"
        );
        _;
    }

    // Manage pairs
    function addPair(Pair calldata _pair)
        public
        onlyGov
        feedOk(_pair.feed)
        groupListed(_pair.groupIndex)
        feeListed(_pair.feeIndex)
    {
        require(!isPairListed[_pair.from][_pair.to], "PAIR_ALREADY_LISTED");

        pairs[pairsCount] = _pair;
        isPairListed[_pair.from][_pair.to] = true;

        emit PairAdded(pairsCount++, _pair.from, _pair.to);
    }

    function addPairs(Pair[] calldata _pairs) external {
        for (uint256 i = 0; i < _pairs.length; i++) {
            addPair(_pairs[i]);
        }
    }

    function updatePair(uint256 _pairIndex, Pair calldata _pair)
        external
        onlyGov
        feedOk(_pair.feed)
        feeListed(_pair.feeIndex)
    {
        Pair storage p = pairs[_pairIndex];
        require(isPairListed[p.from][p.to], "PAIR_NOT_LISTED");

        p.feed = _pair.feed;
        p.spreadP = _pair.spreadP;
        p.feeIndex = _pair.feeIndex;

        emit PairUpdated(_pairIndex);
    }

    // Manage groups
    function addGroup(Group calldata _group) external onlyGov groupOk(_group) {
        groups[groupsCount] = _group;
        emit GroupAdded(groupsCount++, _group.name);
    }

    function updateGroup(uint256 _id, Group calldata _group)
        external
        onlyGov
        groupListed(_id)
        groupOk(_group)
    {
        groups[_id] = _group;
        emit GroupUpdated(_id);
    }

    // Manage fees
    function addFee(Fee calldata _fee) external onlyGov feeOk(_fee) {
        fees[feesCount] = _fee;
        emit FeeAdded(feesCount++, _fee.name);
    }

    function updateFee(uint256 _id, Fee calldata _fee)
        external
        onlyGov
        feeListed(_id)
        feeOk(_fee)
    {
        fees[_id] = _fee;
        emit FeeUpdated(_id);
    }

    // Update collateral open exposure for a group (callbacks)
    function updateGroupCollateral(
        uint256 _pairIndex,
        uint256 _amount,
        bool _long,
        bool _increase
    ) external {
        require(msg.sender == storageT.callbacks(), "CALLBACKS_ONLY");

        uint256[2] storage collateralOpen = groupsCollaterals[
            pairs[_pairIndex].groupIndex
        ];
        uint256 index = _long ? 0 : 1;

        if (_increase) {
            collateralOpen[index] += _amount;
        } else {
            collateralOpen[index] = collateralOpen[index] > _amount
                ? collateralOpen[index] - _amount
                : 0;
        }
    }

    // Fetch relevant info for order (aggregator)
    function pairJob(uint256 _pairIndex)
        external
        returns (
            string memory,
            string memory,
            bytes32,
            uint256
        )
    {
        require(
            msg.sender == address(storageT.priceAggregator()),
            "AGGREGATOR_ONLY"
        );

        Pair memory p = pairs[_pairIndex];
        require(isPairListed[p.from][p.to], "PAIR_NOT_LISTED");

        return (p.from, p.to, groups[p.groupIndex].job, currentOrderId++);
    }

    // Getters (pairs & groups)
    function pairFeed(uint256 _pairIndex) external view returns (Feed memory) {
        return pairs[_pairIndex].feed;
    }

    function pairSpreadP(uint256 _pairIndex) external view returns (uint256) {
        return pairs[_pairIndex].spreadP;
    }

    function pairMinLeverage(uint256 _pairIndex)
        external
        view
        returns (uint256)
    {
        return groups[pairs[_pairIndex].groupIndex].minLeverage;
    }

    function pairMaxLeverage(uint256 _pairIndex)
        external
        view
        returns (uint256)
    {
        return groups[pairs[_pairIndex].groupIndex].maxLeverage;
    }

    function groupMaxCollateral(uint256 _pairIndex)
        external
        view
        returns (uint256)
    {
        return
            (groups[pairs[_pairIndex].groupIndex].maxCollateralP *
                storageT.vault().currentBalanceDai()) / 100;
    }

    function groupCollateral(uint256 _pairIndex, bool _long)
        external
        view
        returns (uint256)
    {
        return groupsCollaterals[pairs[_pairIndex].groupIndex][_long ? 0 : 1];
    }

    function guaranteedSlEnabled(uint256 _pairIndex)
        external
        view
        returns (bool)
    {
        return pairs[_pairIndex].groupIndex == 0; // crypto only
    }

    // Getters (fees)
    function pairOpenFeeP(uint256 _pairIndex) external view returns (uint256) {
        return fees[pairs[_pairIndex].feeIndex].openFeeP;
    }

    function pairCloseFeeP(uint256 _pairIndex) external view returns (uint256) {
        return fees[pairs[_pairIndex].feeIndex].closeFeeP;
    }

    function pairOracleFeeP(uint256 _pairIndex)
        external
        view
        returns (uint256)
    {
        return fees[pairs[_pairIndex].feeIndex].oracleFeeP;
    }

    function pairNftLimitOrderFeeP(uint256 _pairIndex)
        external
        view
        returns (uint256)
    {
        return fees[pairs[_pairIndex].feeIndex].nftLimitOrderFeeP;
    }

    function pairReferralFeeP(uint256 _pairIndex)
        external
        view
        returns (uint256)
    {
        return fees[pairs[_pairIndex].feeIndex].referralFeeP;
    }

    function pairMinLevPosDai(uint256 _pairIndex)
        external
        view
        returns (uint256)
    {
        return fees[pairs[_pairIndex].feeIndex].minLevPosDai;
    }

    // Getters (backend)
    function pairsBackend(uint256 _index)
        external
        view
        returns (
            Pair memory,
            Group memory,
            Fee memory
        )
    {
        Pair memory p = pairs[_index];
        return (p, groups[p.groupIndex], fees[p.feeIndex]);
    }
}

