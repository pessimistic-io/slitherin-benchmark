// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IGambitTradingStorageV1.sol";

import "./GambitErrorsV1.sol";

contract GambitPairsStorageV1 {
    // Contracts (constant)
    IGambitTradingStorageV1 public immutable storageT; // FIXED: make it immutable

    // Params (constant)
    uint constant MIN_LEVERAGE = 2e18;
    uint constant MAX_LEVERAGE = 1000e18;

    // Custom data types
    enum FeedCalculation {
        DEFAULT,
        INVERT,
        COMBINE
    }

    /// @dev Feed struct defins price sources for a pair
    struct Feed {
        address feed1; // chainlink's first feed. e.g., BTC/USD feed
        address feed2; // chainlink's second feed. feed2 is required if feed1 cannot provide price for the pair (e.g., LINK/BTC)
        bytes32 priceId1; // pyth network's price id. e.g., 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43 for BTC/USD
        bytes32 priceId2; // DEPRECATED
        // direction of chainlink feeds' price. (not pyth's price)
        // Examples:
        //  - BTC/USD pair with chainlink's BTC/USD feed => DEFAULT
        //  - USD/JPY pair with chainlink's JPY/USD feed => INVERT
        //  - ETH/BTC pair with chainlink's ETH/USD and BTC/USD feeds => COMBINE
        FeedCalculation feedCalculation;
        uint maxDeviationP;
    } // PRECISION (%)

    struct Pair {
        string from;
        string to;
        Feed feed;
        uint confMultiplierP; // PRECISION
        uint groupIndex;
        uint feeIndex;
    }

    struct Group {
        string name;
        uint minLeverage;
        uint maxLeverage;
        uint maxCollateralP; // %
    }
    struct Fee {
        string name;
        uint openFeeP; // PRECISION (% of leveraged pos)
        uint closeFeeP; // PRECISION (% of leveraged pos)
        uint oracleFee; // 1e6 (USDC) or 1e18 (DAI)
        uint nftLimitOrderFeeP; // PRECISION (% of leveraged pos)
        uint referralFeeP; // PRECISION (% of leveraged pos)
        uint minLevPosUsdc; // 1e6 (USDC) or 1e18 (DAI) (collateral x leverage, useful for min fee)
    }

    // State
    uint public currentOrderId;

    uint public pairsCount;
    uint public groupsCount;
    uint public feesCount;

    mapping(uint => Pair) public pairs;
    mapping(uint => Group) public groups;
    mapping(uint => Fee) public fees;

    mapping(string => mapping(string => bool)) public isPairListed;

    mapping(uint => uint[2]) public groupsCollaterals; // (long, short)

    mapping(uint => uint) public pairExposureUtilsP; // (pairIndex => exposure utility percent)

    // Events
    event PairAdded(uint indexed index, string from, string to);
    event PairUpdated(uint indexed index);

    event GroupAdded(uint indexed index, string name);
    event GroupUpdated(uint indexed index);

    event FeeAdded(uint indexed index, string name);
    event FeeUpdated(uint indexed index);

    event GroupCollateralUpdated(uint indexed index, bool isLong, uint amount);

    event PairExposureUtilsPUpdated(
        uint indexed pairIndex,
        uint pairExposureUtilsP
    );

    constructor(IGambitTradingStorageV1 _storageT, uint _currentOrderId) {
        if (_currentOrderId == 0) revert GambitErrorsV1.WrongParams();
        storageT = _storageT;
        currentOrderId = _currentOrderId;
    }

    // Modifiers
    modifier onlyGov() {
        if (msg.sender != storageT.gov()) revert GambitErrorsV1.NotGov();
        _;
    }

    modifier groupListed(uint _groupIndex) {
        if (groups[_groupIndex].minLeverage == 0)
            revert GambitErrorsV1.GroupNotListed();
        _;
    }
    modifier feeListed(uint _feeIndex) {
        if (fees[_feeIndex].openFeeP == 0) revert GambitErrorsV1.FeeNotListed();
        _;
    }

    modifier feedOk(Feed calldata _feed) {
        // note that we don't check chainlink feeds here because it can be disabled
        if (_feed.maxDeviationP == 0 || _feed.priceId1 == bytes32(0))
            revert GambitErrorsV1.WrongFeed();
        _;
    }
    modifier groupOk(Group calldata _group) {
        if (
            _group.minLeverage < MIN_LEVERAGE ||
            _group.maxLeverage > MAX_LEVERAGE ||
            _group.minLeverage >= _group.maxLeverage
        ) revert GambitErrorsV1.WrongGroup();
        _;
    }
    modifier feeOk(Fee calldata _fee) {
        if (
            _fee.openFeeP == 0 ||
            _fee.openFeeP >= 100e10 || // naive max check up to 100%
            _fee.closeFeeP == 0 ||
            _fee.closeFeeP >= 100e10 || // naive max check up to 100%
            // _fee.oracleFee == 0 || // NOTE: we allow zero oracle fee
            _fee.nftLimitOrderFeeP == 0 ||
            _fee.nftLimitOrderFeeP >= 100e10 || // naive max check up to 100%
            _fee.referralFeeP == 0 ||
            _fee.referralFeeP >= 100e10 || // naive max check up to 100%
            _fee.minLevPosUsdc == 0
        ) revert GambitErrorsV1.WrongFee();
        _;
    }

    // Manage pairs
    function addPair(
        Pair calldata _pair
    )
        public
        onlyGov
        feedOk(_pair.feed)
        groupListed(_pair.groupIndex)
        feeListed(_pair.feeIndex)
    {
        if (isPairListed[_pair.from][_pair.to])
            revert GambitErrorsV1.AlreadyListedPair();

        pairs[pairsCount] = _pair;
        isPairListed[_pair.from][_pair.to] = true;

        emit PairAdded(pairsCount++, _pair.from, _pair.to);
    }

    function addPairs(Pair[] calldata _pairs) external {
        for (uint i = 0; i < _pairs.length; i++) {
            addPair(_pairs[i]);
        }
    }

    function updatePair(
        uint _pairIndex,
        Pair calldata _pair
    ) external onlyGov feedOk(_pair.feed) feeListed(_pair.feeIndex) {
        Pair storage p = pairs[_pairIndex];
        if (!isPairListed[p.from][p.to]) revert GambitErrorsV1.PairNotListed();

        p.feed = _pair.feed;
        p.confMultiplierP = _pair.confMultiplierP;
        p.feeIndex = _pair.feeIndex;

        emit PairUpdated(_pairIndex);
    }

    // Manage groups
    function addGroup(Group calldata _group) external onlyGov groupOk(_group) {
        groups[groupsCount] = _group;
        emit GroupAdded(groupsCount++, _group.name);
    }

    function updateGroup(
        uint _id,
        Group calldata _group
    ) external onlyGov groupListed(_id) groupOk(_group) {
        groups[_id] = _group;
        emit GroupUpdated(_id);
    }

    // Manage fees
    function addFee(Fee calldata _fee) external onlyGov feeOk(_fee) {
        fees[feesCount] = _fee;
        emit FeeAdded(feesCount++, _fee.name);
    }

    function updateFee(
        uint _id,
        Fee calldata _fee
    ) external onlyGov feeListed(_id) feeOk(_fee) {
        fees[_id] = _fee;
        emit FeeUpdated(_id);
    }

    // Update collateral open exposure for a group (callbacks)
    function updateGroupCollateral(
        uint _pairIndex,
        uint _amount,
        bool _long,
        bool _increase
    ) external {
        if (msg.sender != storageT.callbacks())
            revert GambitErrorsV1.NotCallbacks();

        uint groupIndex = pairs[_pairIndex].groupIndex;
        uint[2] storage collateralOpen = groupsCollaterals[groupIndex];
        uint index = _long ? 0 : 1;

        if (_increase) {
            collateralOpen[index] += _amount;
        } else {
            collateralOpen[index] = collateralOpen[index] > _amount
                ? collateralOpen[index] - _amount
                : 0;
        }

        emit GroupCollateralUpdated(groupIndex, _long, collateralOpen[index]);
    }

    function updatePairExposureUtilsP(
        uint _pairIndex,
        uint _pairExposureUtilsP
    ) external onlyGov {
        if (_pairExposureUtilsP == 0) revert GambitErrorsV1.ZeroValue();
        pairExposureUtilsP[_pairIndex] = _pairExposureUtilsP;
        emit PairExposureUtilsPUpdated(_pairIndex, _pairExposureUtilsP);
    }

    // Fetch relevant info for order (aggregator)
    function pairJob(
        uint _pairIndex
    ) external returns (string memory, string memory, uint) {
        if (msg.sender != address(storageT.priceAggregator()))
            revert GambitErrorsV1.NotAggregator();

        Pair memory p = pairs[_pairIndex];
        if (!isPairListed[p.from][p.to]) revert GambitErrorsV1.PairNotListed();

        return (p.from, p.to, currentOrderId++);
    }

    // Getters (pairs & groups)
    function pairFeed(uint _pairIndex) external view returns (Feed memory) {
        return pairs[_pairIndex].feed;
    }

    function pairConfMultiplierP(uint _pairIndex) external view returns (uint) {
        return pairs[_pairIndex].confMultiplierP;
    }

    function pairMinLeverage(uint _pairIndex) external view returns (uint) {
        return groups[pairs[_pairIndex].groupIndex].minLeverage;
    }

    function pairMaxLeverage(uint _pairIndex) external view returns (uint) {
        return groups[pairs[_pairIndex].groupIndex].maxLeverage;
    }

    function groupMaxCollateralP(uint _pairIndex) external view returns (uint) {
        return groups[pairs[_pairIndex].groupIndex].maxCollateralP;
    }

    function groupMaxCollateral(uint _pairIndex) external view returns (uint) {
        return
            (groups[pairs[_pairIndex].groupIndex].maxCollateralP *
                storageT.vault().currentBalanceUsdc()) / 100;
    }

    function groupCollateral(
        uint _pairIndex,
        bool _long
    ) external view returns (uint) {
        return groupsCollaterals[pairs[_pairIndex].groupIndex][_long ? 0 : 1];
    }

    function guaranteedSlEnabled(uint _pairIndex) external view returns (bool) {
        return pairs[_pairIndex].groupIndex == 0; // crypto only
    }

    // Getters (fees)
    function pairOpenFeeP(uint _pairIndex) external view returns (uint) {
        return fees[pairs[_pairIndex].feeIndex].openFeeP;
    }

    function pairCloseFeeP(uint _pairIndex) external view returns (uint) {
        return fees[pairs[_pairIndex].feeIndex].closeFeeP;
    }

    /// @notice NOT USED in contract
    function pairOracleFee(uint _pairIndex) external view returns (uint) {
        return fees[pairs[_pairIndex].feeIndex].oracleFee;
    }

    function pairNftLimitOrderFeeP(
        uint _pairIndex
    ) external view returns (uint) {
        return fees[pairs[_pairIndex].feeIndex].nftLimitOrderFeeP;
    }

    /// @notice NOT USED in contract
    function pairReferralFeeP(uint _pairIndex) external view returns (uint) {
        return fees[pairs[_pairIndex].feeIndex].referralFeeP;
    }

    function pairMinLevPosUsdc(uint _pairIndex) external view returns (uint) {
        return fees[pairs[_pairIndex].feeIndex].minLevPosUsdc;
    }

    // Getters (backend)
    function pairsBackend(
        uint _index
    ) external view returns (Pair memory, Group memory, Fee memory) {
        Pair memory p = pairs[_index];
        return (p, groups[p.groupIndex], fees[p.feeIndex]);
    }
}

