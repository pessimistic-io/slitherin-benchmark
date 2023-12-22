// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ITradingStorage.sol";


contract PairInfos {

    uint256 constant PRECISION = 1e10;     
    uint256 constant LIQ_THRESHOLD_P = 90; // -90% (of collateral)
    
    struct PairParams{
        uint256 onePercentDepthAbove; 
        uint256 onePercentDepthBelow; 
        uint256 rolloverFeePerBlockP; 
        uint256 fundingFeePerBlockP;  
    }

    struct PairFundingFees{
        int256 accPerOiLong; 
        int256 accPerOiShort; 
        uint256 lastUpdateBlock;
    }

    struct PairRolloverFees{
        uint256 accPerCollateral; 
        uint256 lastUpdateBlock;
    }

    struct TradeInitialAccFees{
        uint256 rollover; 
        int256 funding;   
        bool openedAfterUpdate;
    }

    ITradingStorage public storageT;
    address public manager;

    uint256 public maxNegativePnlOnOpenP;

    mapping(uint256 => PairParams) public pairParams;
    mapping(uint => PairFundingFees) public pairFundingFees;
    mapping(uint256 => PairRolloverFees) public pairRolloverFees;

    mapping(
        address => mapping(
            uint256 => mapping(
                uint256 => TradeInitialAccFees
            )
        )
    ) public tradeInitialAccFees;

    event ManagerUpdated(address value);
    event MaxNegativePnlOnOpenPUpdated(uint256 value);
    event PairParamsUpdated(uint256 pairIndex, PairParams value);
    event OnePercentDepthUpdated(uint256 pairIndex, uint256 valueAbove, uint256 valueBelow);
    event RolloverFeePerBlockPUpdated(uint256 pairIndex, uint256 value);
    event FundingFeePerBlockPUpdated(uint256 pairIndex, uint256 value);

    event TradeInitialAccFeesStored(
        address trader,
        uint256 pairIndex,
        uint256 index,
        uint256 rollover,
        int256 funding
    );

    event AccFundingFeesStored(uint256 pairIndex, int256 valueLong, int256 valueShort);
    event AccRolloverFeesStored(uint256 pairIndex, uint256 value);

    event FeesCharged(
        uint256 pairIndex,
        bool long,
        uint256 collateral, 
        uint256 leverage,
        int256 percentProfit, 
        uint256 rolloverFees, 
        int256 fundingFees   
    );

    error PairInfosWrongParameters();
    error PairInfosInvalidGovAddress(address account);
    error PairInfosInvalidManagerAddress(address account);
    error PairInfosInvalidCallbacksContract(address account);
    error PairInfosInvalidAddress(address account);
    error PairInfosTooHigh();

    modifier onlyGov(){
        if (msg.sender != storageT.gov()) {
            revert PairInfosInvalidGovAddress(msg.sender);
        }
        _;
    }
    modifier onlyManager(){
        if (msg.sender != manager) {
            revert PairInfosInvalidManagerAddress(msg.sender);
        }
        _;
    }
    modifier onlyCallbacks(){
        if (msg.sender != storageT.callbacks()) {
            revert PairInfosInvalidCallbacksContract(msg.sender);
        }
        _;
    }

    constructor(
        ITradingStorage _storageT,
        address _manager,
        uint256 _maxNegativePnlOnOpenP
    ) {
        if (address(_storageT) == address(0) || 
            _manager == address(0) ||
            _maxNegativePnlOnOpenP == 0) {
            revert PairInfosWrongParameters();
        }

        storageT = _storageT;
        manager = _manager;
        maxNegativePnlOnOpenP = _maxNegativePnlOnOpenP;
    }

    function setManager(address _manager) external onlyGov{
        if (_manager == address(0)) {
            revert PairInfosInvalidAddress(address(0));
        }
        manager = _manager;

        emit ManagerUpdated(_manager);
    }

    function setMaxNegativePnlOnOpenP(uint256 value) external onlyManager{
        maxNegativePnlOnOpenP = value;

        emit MaxNegativePnlOnOpenPUpdated(value);
    }

    function setPairParamsArray(
        uint256[] memory indices,
        PairParams[] memory values
    ) external onlyManager{
        if (indices.length != values.length) revert PairInfosWrongParameters();

        for(uint256 i = 0; i < indices.length; i++){
            setPairParams(indices[i], values[i]);
        }
    }

    function setOnePercentDepthArray(
        uint256[] memory indices,
        uint256[] memory valuesAbove,
        uint256[] memory valuesBelow
    ) external onlyManager{
        if (indices.length != valuesAbove.length || indices.length != valuesBelow.length) {
            revert PairInfosWrongParameters();
        }

        for(uint256 i = 0; i < indices.length; i++){
            setOnePercentDepth(indices[i], valuesAbove[i], valuesBelow[i]);
        }
    }

    function setRolloverFeePerBlockPArray(
        uint256[] memory indices,
        uint256[] memory values
    ) external onlyManager{
        if (indices.length != values.length) revert PairInfosWrongParameters();

        for(uint256 i = 0; i < indices.length; i++){
            setRolloverFeePerBlockP(indices[i], values[i]);
        }
    }

    function setFundingFeePerBlockPArray(
        uint256[] memory indices,
        uint256[] memory values
    ) external onlyManager{
        if (indices.length != values.length) revert PairInfosWrongParameters();

        for(uint256 i = 0; i < indices.length; i++){
            setFundingFeePerBlockP(indices[i], values[i]);
        }
    }

    function storeTradeInitialAccFees(
        address trader,
        uint256 pairIndex,
        uint256 index,
        bool long
    ) external onlyCallbacks{
        storeAccFundingFees(pairIndex);

        TradeInitialAccFees storage t = tradeInitialAccFees[trader][pairIndex][index];

        t.rollover = getPendingAccRolloverFees(pairIndex);

        t.funding = long ? 
            pairFundingFees[pairIndex].accPerOiLong :
            pairFundingFees[pairIndex].accPerOiShort;

        t.openedAfterUpdate = true;

        emit TradeInitialAccFeesStored(trader, pairIndex, index, t.rollover, t.funding);
    }

    function getTradeValue(
        address trader,
        uint256 pairIndex,
        uint256 index,
        bool long,
        uint256 collateral,  
        uint256 leverage,
        int256 percentProfit,
        uint256 closingFee    
    ) external onlyCallbacks returns(uint256 amount){ 
        storeAccFundingFees(pairIndex);

        uint256 r = getTradeRolloverFee(trader, pairIndex, index, collateral);
        int256 f = getTradeFundingFee(trader, pairIndex, index, long, collateral, leverage);

        amount = getTradeValuePure(collateral, percentProfit, r, f, closingFee);

        emit FeesCharged(pairIndex, long, collateral, leverage, percentProfit, r, f);
    }

    function getTradePriceImpact(
        uint256 openPrice,        
        uint256 pairIndex,
        bool long,
        uint256 tradeOpenInterest 
    ) external view returns(
        uint256 priceImpactP,     
        uint256 priceAfterImpact  
    ){
        (priceImpactP, priceAfterImpact) = getTradePriceImpactPure(
            openPrice,
            long,
            storageT.openInterestStable(pairIndex, long ? 0 : 1),
            tradeOpenInterest,
            long ?
                pairParams[pairIndex].onePercentDepthAbove :
                pairParams[pairIndex].onePercentDepthBelow
        );
    }

    function getTradeLiquidationPrice(
        address trader,
        uint256 pairIndex,
        uint256 index,
        uint256 openPrice, 
        bool long,
        uint256 collateral, 
        uint256 leverage
    ) external view returns(uint256){ 
        return getTradeLiquidationPricePure(
            openPrice,
            long,
            collateral,
            leverage,
            getTradeRolloverFee(trader, pairIndex, index, collateral),
            getTradeFundingFee(trader, pairIndex, index, long, collateral, leverage)
        );
    }

    function getPairInfos(uint256[] memory indices) external view returns(
        PairParams[] memory,
        PairRolloverFees[] memory,
        PairFundingFees[] memory
    ){
        PairParams[] memory params = new PairParams[](indices.length);
        PairRolloverFees[] memory rolloverFees = new PairRolloverFees[](indices.length);
        PairFundingFees[] memory fundingFees = new PairFundingFees[](indices.length);

        for(uint256 i = 0; i < indices.length; i++){
            uint256 index = indices[i];

            params[i] = pairParams[index];
            rolloverFees[i] = pairRolloverFees[index];
            fundingFees[i] = pairFundingFees[index];
        }

        return (params, rolloverFees, fundingFees);
    }

    function getOnePercentDepthAbove(uint256 pairIndex) external view returns(uint256){
        return pairParams[pairIndex].onePercentDepthAbove;
    }

    function getOnePercentDepthBelow(uint256 pairIndex) external view returns(uint256){
        return pairParams[pairIndex].onePercentDepthBelow;
    }

    function getRolloverFeePerBlockP(uint256 pairIndex) external view returns(uint256){
        return pairParams[pairIndex].rolloverFeePerBlockP;
    }

    function getFundingFeePerBlockP(uint256 pairIndex) external view returns(uint256){
        return pairParams[pairIndex].fundingFeePerBlockP;
    }

    function getAccRolloverFees(uint256 pairIndex) external view returns(uint256){
        return pairRolloverFees[pairIndex].accPerCollateral;
    }

    function getAccRolloverFeesUpdateBlock(uint256 pairIndex) external view returns(uint256){
        return pairRolloverFees[pairIndex].lastUpdateBlock;
    }

    function getAccFundingFeesLong(uint256 pairIndex) external view returns(int256){
        return pairFundingFees[pairIndex].accPerOiLong;
    }

    function getAccFundingFeesShort(uint256 pairIndex) external view returns(int256){
        return pairFundingFees[pairIndex].accPerOiShort;
    }

    function getAccFundingFeesUpdateBlock(uint256 pairIndex) external view returns(uint256){
        return pairFundingFees[pairIndex].lastUpdateBlock;
    }

    function getTradeInitialAccRolloverFeesPerCollateral(
        address trader,
        uint256 pairIndex,
        uint256 index
    ) external view returns(uint256){
        return tradeInitialAccFees[trader][pairIndex][index].rollover;
    }

    function getTradeInitialAccFundingFeesPerOi(
        address trader,
        uint256 pairIndex,
        uint256 index
    ) external view returns(int256){
        return tradeInitialAccFees[trader][pairIndex][index].funding;
    }

    function getTradeOpenedAfterUpdate(
        address trader,
        uint256 pairIndex,
        uint256 index
    ) external view returns(bool){
        return tradeInitialAccFees[trader][pairIndex][index].openedAfterUpdate;
    }

    function setPairParams(uint256 pairIndex, PairParams memory value) public onlyManager{
        storeAccRolloverFees(pairIndex);
        storeAccFundingFees(pairIndex);

        pairParams[pairIndex] = value;

        emit PairParamsUpdated(pairIndex, value);
    }

    function setOnePercentDepth(
        uint256 pairIndex,
        uint256 valueAbove,
        uint256 valueBelow
    ) public onlyManager{
        PairParams storage p = pairParams[pairIndex];

        p.onePercentDepthAbove = valueAbove;
        p.onePercentDepthBelow = valueBelow;
        
        emit OnePercentDepthUpdated(pairIndex, valueAbove, valueBelow);
    }
    
    function setRolloverFeePerBlockP(uint256 pairIndex, uint256 value) public onlyManager{
        if (value > 25000000) revert PairInfosTooHigh();

        storeAccRolloverFees(pairIndex);

        pairParams[pairIndex].rolloverFeePerBlockP = value;
        
        emit RolloverFeePerBlockPUpdated(pairIndex, value);
    }
    
    function setFundingFeePerBlockP(uint256 pairIndex, uint256 value) public onlyManager{
        if (value > 10000000) revert PairInfosTooHigh();

        storeAccFundingFees(pairIndex);

        pairParams[pairIndex].fundingFeePerBlockP = value;
        
        emit FundingFeePerBlockPUpdated(pairIndex, value);
    }

    function getPendingAccRolloverFees(
        uint256 pairIndex
    ) public view returns(uint256){ 
        PairRolloverFees storage r = pairRolloverFees[pairIndex];
        
        return r.accPerCollateral +
            (block.number - r.lastUpdateBlock)
            * pairParams[pairIndex].rolloverFeePerBlockP
            * 1e18 / PRECISION / 100;
    }

    function getPendingAccFundingFees(uint256 pairIndex) public view returns(
        int256 valueLong,
        int256 valueShort
    ){
        PairFundingFees storage f = pairFundingFees[pairIndex];

        valueLong = f.accPerOiLong;
        valueShort = f.accPerOiShort;

        int256 openInterestStableLong = int256(storageT.openInterestStable(pairIndex, 0));
        int256 openInterestStableShort = int256(storageT.openInterestStable(pairIndex, 1));

        int256 fundingFeesPaidByLongs = (openInterestStableLong - openInterestStableShort)
            * int256(block.number - f.lastUpdateBlock)
            * int256(pairParams[pairIndex].fundingFeePerBlockP)
            / int256(PRECISION) / 100;

        if(openInterestStableLong > 0){
            valueLong += fundingFeesPaidByLongs * 1e18
                / openInterestStableLong;
        }

        if(openInterestStableShort > 0){
            valueShort += fundingFeesPaidByLongs * 1e18 * (-1)
                / openInterestStableShort;
        }
    }

    function getTradeRolloverFee(
        address trader,
        uint256 pairIndex,
        uint256 index,
        uint256 collateral 
    ) public view returns(uint256){ 
        TradeInitialAccFees memory t = tradeInitialAccFees[trader][pairIndex][index];

        if(!t.openedAfterUpdate){
            return 0;
        }

        return getTradeRolloverFeePure(
            t.rollover,
            getPendingAccRolloverFees(pairIndex),
            collateral
        );
    }

    function getTradeFundingFee(
        address trader,
        uint256 pairIndex,
        uint256 index,
        bool long,
        uint256 collateral, 
        uint256 leverage
    ) public view returns(
        int256 // Positive => Fee, Negative => Reward
    ){
        TradeInitialAccFees memory t = tradeInitialAccFees[trader][pairIndex][index];

        if(!t.openedAfterUpdate){
            return 0;
        }

        (int256 pendingLong, int256 pendingShort) = getPendingAccFundingFees(pairIndex);

        return getTradeFundingFeePure(
            t.funding,
            long ? pendingLong : pendingShort,
            collateral,
            leverage
        );
    }
    
    function getTradeRolloverFeePure(
        uint256 accRolloverFeesPerCollateral,
        uint256 endAccRolloverFeesPerCollateral,
        uint256 collateral 
    ) public pure returns(uint256){ 
        return (endAccRolloverFeesPerCollateral - accRolloverFeesPerCollateral)
            * collateral / 1e18;
    }

    function getTradePriceImpactPure(
        uint256 openPrice,        
        bool long,
        uint256 startOpenInterest, 
        uint256 tradeOpenInterest, 
        uint256 onePercentDepth
    ) public pure returns(
        uint256 priceImpactP,      
        uint256 priceAfterImpact   
    ){
        if(onePercentDepth == 0){
            return (0, openPrice);
        }

        priceImpactP = (startOpenInterest + tradeOpenInterest / 2)
            * PRECISION / 1e18 / onePercentDepth;
        
        uint256 priceImpact = priceImpactP * openPrice / PRECISION / 100;

        priceAfterImpact = long ? openPrice + priceImpact : openPrice - priceImpact;
    }

    function getTradeFundingFeePure(
        int256 accFundingFeesPerOi,
        int256 endAccFundingFeesPerOi,
        uint256 collateral,
        uint256 leverage
    ) public pure returns(
        int256 // Positive => Fee, Negative => Reward
    ){
        return (endAccFundingFeesPerOi - accFundingFeesPerOi)
            * int256(collateral) * int256(leverage) / 1e18;
    }

    function getTradeLiquidationPricePure(
        uint256 openPrice,  
        bool long,
        uint256 collateral, 
        uint256 leverage,
        uint256 rolloverFee, 
        int256 fundingFee   
    ) public pure returns(uint256){ 
        int256 liqPriceDistance = int256(openPrice) * (
                int256(collateral * LIQ_THRESHOLD_P / 100)
                - int256(rolloverFee) - fundingFee
            ) / int256(collateral) / int256(leverage);

        int256 liqPrice = long ?
            int256(openPrice) - liqPriceDistance :
            int256(openPrice) + liqPriceDistance;

        return liqPrice > 0 ? uint256(liqPrice) : 0;
    }

    function getTradeValuePure(
        uint256 collateral,   
        int256 percentProfit, 
        uint256 rolloverFee,  
        int256 fundingFee,   
        uint256 closingFee    
    ) public pure returns(uint256){ 
        int256 value = int256(collateral)
            + int256(collateral) * percentProfit / int256(PRECISION) / 100
            - int256(rolloverFee) - fundingFee;

        if(value <= int256(collateral) * int256(100 - LIQ_THRESHOLD_P) / 100){
            return 0;
        }

        value -= int256(closingFee);

        return value > 0 ? uint256(value) : 0;
    }

    function storeAccRolloverFees(uint256 pairIndex) private{
        PairRolloverFees storage r = pairRolloverFees[pairIndex];

        r.accPerCollateral = getPendingAccRolloverFees(pairIndex);
        r.lastUpdateBlock = block.number;

        emit AccRolloverFeesStored(pairIndex, r.accPerCollateral);
    }
    
    function storeAccFundingFees(uint256 pairIndex) private{
        PairFundingFees storage f = pairFundingFees[pairIndex];

        (f.accPerOiLong, f.accPerOiShort) = getPendingAccFundingFees(pairIndex);
        f.lastUpdateBlock = block.number;

        emit AccFundingFeesStored(pairIndex, f.accPerOiLong, f.accPerOiShort);
    }  
}

