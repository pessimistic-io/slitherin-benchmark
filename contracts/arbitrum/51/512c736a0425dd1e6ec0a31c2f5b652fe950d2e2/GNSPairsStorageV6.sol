// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IStorageInterfaceV5.sol";

abstract contract GNSPairsStorageV6 {
    // Contracts (constant)
    StorageInterfaceV5 public storageT;

    // Params (constant)
    uint constant MIN_LEVERAGE = 2;
    uint constant MAX_LEVERAGE = 1000;

    // Custom data types
    enum FeedCalculation {
        DEFAULT,
        INVERT,
        COMBINE
    }
    struct Feed {
        address feed1;
        address feed2;
        FeedCalculation feedCalculation;
        uint maxDeviationP;
    } // PRECISION (%)
    struct Pair {
        string from;
        string to;
        Feed feed;
        uint spreadP; // PRECISION
        uint groupIndex;
        uint feeIndex;
    }
    struct Group {
        string name;
        bytes32 job;
        uint minLeverage;
        uint maxLeverage;
        uint maxCollateralP; // % (of DAI vault current balance)
    }
    struct Fee {
        string name;
        uint openFeeP; // PRECISION (% of leveraged pos)
        uint closeFeeP; // PRECISION (% of leveraged pos)
        uint oracleFeeP; // PRECISION (% of leveraged pos)
        uint nftLimitOrderFeeP; // PRECISION (% of leveraged pos)
        uint referralFeeP; // PRECISION (% of leveraged pos)
        uint minLevPosDai; // 1e18 (collateral x leverage, useful for min fee)
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

    // Events
    event PairAdded(uint index, string from, string to);
    event PairUpdated(uint index);

    event GroupAdded(uint index, string name);
    event GroupUpdated(uint index);

    event FeeAdded(uint index, string name);
    event FeeUpdated(uint index);

    function initialize(StorageInterfaceV5 _storageT, uint _currentOrderId) external virtual;

    // Manage pairs
    function addPair(Pair calldata _pair) public virtual;

    function addPairs(Pair[] calldata _pairs) external virtual;

    function updatePair(uint _pairIndex, Pair calldata _pair) external virtual;

    // Manage groups
    function addGroup(Group calldata _group) external virtual;

    function updateGroup(uint _id, Group calldata _group) external virtual;

    // Manage fees
    function addFee(Fee calldata _fee) external virtual;

    function updateFee(uint _id, Fee calldata _fee) external virtual;

    // Update collateral open exposure for a group (callbacks)
    function updateGroupCollateral(uint _pairIndex, uint _amount, bool _long, bool _increase) external virtual;

    // Fetch relevant info for order (aggregator)
    function pairJob(uint _pairIndex) external virtual returns (string memory, string memory, bytes32, uint);

    // Getters (pairs & groups)
    function pairFeed(uint _pairIndex) external view virtual returns (Feed memory);

    function pairSpreadP(uint _pairIndex) external view virtual returns (uint);

    function pairMinLeverage(uint _pairIndex) external view virtual returns (uint);

    function pairMaxLeverage(uint _pairIndex) external view virtual returns (uint);

    function groupMaxCollateral(uint _pairIndex) external view virtual returns (uint);

    function groupCollateral(uint _pairIndex, bool _long) external view virtual returns (uint);

    function guaranteedSlEnabled(uint _pairIndex) external view virtual returns (bool);

    // Getters (fees)
    function pairOpenFeeP(uint _pairIndex) external view virtual returns (uint);

    function pairCloseFeeP(uint _pairIndex) external view virtual returns (uint);

    function pairOracleFeeP(uint _pairIndex) external view virtual returns (uint);

    function pairNftLimitOrderFeeP(uint _pairIndex) external view virtual returns (uint);

    function pairReferralFeeP(uint _pairIndex) external view virtual returns (uint);

    function pairMinLevPosDai(uint _pairIndex) external view virtual returns (uint);

    // Getters (backend)
    function pairsBackend(uint _index) external view virtual returns (Pair memory, Group memory, Fee memory);
}

