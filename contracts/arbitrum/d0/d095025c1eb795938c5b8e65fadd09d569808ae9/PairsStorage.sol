// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ITradingStorage.sol";


contract PairsStorage {

    uint256 constant MIN_LEVERAGE = 2;
    uint256 constant MAX_LEVERAGE = 1000;

    enum FeedCalculation { DEFAULT, INVERT, COMBINE }
    struct Feed{ address feed1; address feed2; FeedCalculation feedCalculation; uint256 maxDeviationP; } 

    struct Pair{
        string from;
        string to;
        Feed feed;
        uint256 spreadP;            
        uint256 groupIndex;
        uint256 feeIndex;
    }

    struct Group{
        string name;
        bytes32 job;
        uint256 minLeverage;
        uint256 maxLeverage;
        uint256 maxCollateralP;        
    }

    struct Fee{
        string name;
        uint256 openFeeP;              //  % of leveraged pos
        uint256 closeFeeP;             //  % of leveraged pos
        uint256 oracleFeeP;            //  % of leveraged pos
        uint256 executeLimitOrderFeeP;     //  % of leveraged pos
        uint256 referralFeeP;          //  % of leveraged pos
        uint256 minLevPosStable;          // collateral x leverage, useful for min fee
    }

    ITradingStorage public storageT;
    uint256 public currentOrderId;

    uint256 public pairsCount;
    uint256 public groupsCount;
    uint256 public feesCount;

    mapping(uint256 => Pair) public pairs;
    mapping(uint256 => Group) public groups;
    mapping(uint256 => Fee) public fees;

    mapping(string => mapping(string => bool)) public isPairListed;

    mapping(uint256 => uint256[2]) public groupsCollaterals; // (long, short)

    event PairAdded(uint256 index, string from, string to);
    event PairUpdated(uint256 index);

    event GroupAdded(uint256 index, string name);
    event GroupUpdated(uint256 index);
    
    event FeeAdded(uint256 index, string name);
    event FeeUpdated(uint256 index);

    error PairStorageWrongParameters();
    error PairStorageInvalidGovAddress(address account);
    error PairStorageGroupNotListed(uint256 index);
    error PairStorageFeeNotListed(uint256 index);
    error PairStorageWrongFeed();
    error PaitStorageFeed2Missing();
    error PairStorageJobEmpty();
    error PairStotageWrongLeverage();
    error PairStotageWrongFees();
    error PairStorageAlreadyListed();
    error PairStorageNotListed();
    error PairStorageInvalidCallbacksContract(address account);
    error PairStorageInvalidAggregatorContract(address account);
    
    modifier onlyGov(){
        if (msg.sender != storageT.gov()) {
            revert PairStorageInvalidGovAddress(msg.sender);
        }
        _;
    }
    
    modifier groupListed(uint256 _groupIndex){
        if (groups[_groupIndex].minLeverage == 0) {
            revert PairStorageGroupNotListed(_groupIndex);
        }
        _;
    }

    modifier feeListed(uint256 _feeIndex){
        if (fees[_feeIndex].openFeeP == 0) {
            revert PairStorageFeeNotListed(_feeIndex);
        }
        _;
    }

    modifier feedOk(Feed calldata _feed){
        if (_feed.maxDeviationP == 0 || _feed.feed1 == address(0)) revert PairStorageWrongFeed();
        if (_feed.feedCalculation == FeedCalculation.COMBINE && _feed.feed2 == address(0)) revert PaitStorageFeed2Missing();
        _;
    }

    modifier groupOk(Group calldata _group){
        if (_group.job == bytes32(0)) revert PairStorageJobEmpty();
        if (_group.minLeverage < MIN_LEVERAGE || _group.maxLeverage > MAX_LEVERAGE ||
            _group.minLeverage >= _group.maxLeverage) {
            revert PairStotageWrongLeverage();
        }
        _;
    }
    
    modifier feeOk(Fee calldata _fee){
        if (_fee.openFeeP == 0 || _fee.closeFeeP == 0 || _fee.oracleFeeP == 0 ||
            _fee.executeLimitOrderFeeP == 0 || _fee.referralFeeP == 0 || _fee.minLevPosStable == 0) {
            revert PairStotageWrongFees();
        }
        _;
    }

    constructor(ITradingStorage _storageT, uint256 _currentOrderId) {
        if (address(_storageT) == address(0) || _currentOrderId == 0) revert PairStorageWrongParameters();

        storageT = _storageT;
        currentOrderId = _currentOrderId;
    }

    function addPairs(Pair[] calldata _pairs) external{
        for(uint256 i = 0; i < _pairs.length; i++){
            addPair(_pairs[i]);
        }
    }
    function updatePair(uint256 _pairIndex, Pair calldata _pair) external onlyGov feedOk(_pair.feed) feeListed(_pair.feeIndex){
        Pair storage p = pairs[_pairIndex];
        if (!isPairListed[p.from][p.to]) revert PairStorageNotListed();

        p.feed = _pair.feed;
        p.spreadP = _pair.spreadP;
        p.feeIndex = _pair.feeIndex;
        
        emit PairUpdated(_pairIndex);
    }

    function addGroup(Group calldata _group) external onlyGov groupOk(_group){
        groups[groupsCount] = _group;
        emit GroupAdded(groupsCount++, _group.name);
    }

    function updateGroup(uint256 _id, Group calldata _group) external onlyGov groupListed(_id) groupOk(_group){
        groups[_id] = _group;
        emit GroupUpdated(_id);
    }

    function addFee(Fee calldata _fee) external onlyGov feeOk(_fee){
        fees[feesCount] = _fee;
        emit FeeAdded(feesCount++, _fee.name);
    }

    function updateFee(uint256 _id, Fee calldata _fee) external onlyGov feeListed(_id) feeOk(_fee){
        fees[_id] = _fee;
        emit FeeUpdated(_id);
    }

    function updateGroupCollateral(uint256 _pairIndex, uint256 _amount, bool _long, bool _increase) external{
        if (msg.sender != storageT.callbacks()) revert PairStorageInvalidCallbacksContract(msg.sender);

        uint256[2] storage collateralOpen = groupsCollaterals[pairs[_pairIndex].groupIndex];
        uint256 index = _long ? 0 : 1;

        if(_increase){
            collateralOpen[index] += _amount;
        }else{
            collateralOpen[index] = collateralOpen[index] > _amount ? collateralOpen[index] - _amount : 0;
        }
    }

    function pairJob(uint256 _pairIndex) external returns(string memory, string memory, bytes32, uint256){
        if (msg.sender != address(storageT.priceAggregator())) revert PairStorageInvalidAggregatorContract(msg.sender);
        
        Pair memory p = pairs[_pairIndex];
        if (!isPairListed[p.from][p.to]) revert PairStorageNotListed();
        
        return (p.from, p.to, groups[p.groupIndex].job, currentOrderId++);
    }

    function pairFeed(uint256 _pairIndex) external view returns(Feed memory){
        return pairs[_pairIndex].feed;
    }

    function pairSpreadP(uint256 _pairIndex) external view returns(uint256){
        return pairs[_pairIndex].spreadP;
    }

    function pairMinLeverage(uint256 _pairIndex) external view returns(uint256){
        return groups[pairs[_pairIndex].groupIndex].minLeverage;
    }

    function pairMaxLeverage(uint256 _pairIndex) external view returns(uint256){
        return groups[pairs[_pairIndex].groupIndex].maxLeverage;
    }

    function groupMaxCollateral(uint256 _pairIndex) external view returns(uint256){
        return groups[pairs[_pairIndex].groupIndex].maxCollateralP * storageT.workPool().currentBalanceStable() / 100;
    }

    function groupCollateral(uint256 _pairIndex, bool _long) external view returns(uint256){
        return groupsCollaterals[pairs[_pairIndex].groupIndex][_long ? 0 : 1];
    }
    
    function guaranteedSlEnabled(uint256 _pairIndex) external view returns(bool){
        return pairs[_pairIndex].groupIndex == 0; // crypto only
    }

    function pairOpenFeeP(uint256 _pairIndex) external view returns(uint256){ 
        return fees[pairs[_pairIndex].feeIndex].openFeeP;
    }

    function pairCloseFeeP(uint256 _pairIndex) external view returns(uint256){ 
        return fees[pairs[_pairIndex].feeIndex].closeFeeP; 
    }

    function pairOracleFeeP(uint256 _pairIndex) external view returns(uint256){ 
        return fees[pairs[_pairIndex].feeIndex].oracleFeeP; 
    }

    function pairExecuteLimitOrderFeeP(uint256 _pairIndex) external view returns(uint256){ 
        return fees[pairs[_pairIndex].feeIndex].executeLimitOrderFeeP; 
    }

    function pairReferralFeeP(uint256 _pairIndex) external view returns(uint256){ 
        return fees[pairs[_pairIndex].feeIndex].referralFeeP; 
    }

    function pairMinLevPosStable(uint256 _pairIndex) external view returns(uint256){
        return fees[pairs[_pairIndex].feeIndex].minLevPosStable;
    }

    function pairsBackend(uint256 _index) external view returns(Pair memory, Group memory, Fee memory){
        Pair memory p = pairs[_index];
        return (p, groups[p.groupIndex], fees[p.feeIndex]);
    }

    function addPair(Pair calldata _pair) public onlyGov feedOk(_pair.feed) groupListed(_pair.groupIndex) feeListed(_pair.feeIndex){
        if (isPairListed[_pair.from][_pair.to]) revert PairStorageAlreadyListed();
        
        pairs[pairsCount] = _pair;
        isPairListed[_pair.from][_pair.to] = true;
        
        emit PairAdded(pairsCount++, _pair.from, _pair.to);
    }
}

