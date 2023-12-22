// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import "./PoolStorage.sol";

import "./IERC20.sol";
import "./IPool.sol";
import "./IMarket.sol";
import "./IInterestLogic.sol";
import "./IMarketPriceFeed.sol";

import "./ERC20.sol";
import "./PoolDataStructure.sol";
import "./SafeMath.sol";
import "./SignedSafeMath.sol";
import "./SafeCast.sol";
import "./ReentrancyGuard.sol";
import "./TransferHelper.sol";
import "./IVault.sol";
import "./IInviteManager.sol";

contract Pool is ERC20, PoolStorage, ReentrancyGuard {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;

    constructor(
        address _manager,
        address _baseAsset,
        address _WETH,
        string memory _lpTokenName, // usdc pool 1
        string memory _lpTokenSymbol//usdc1
    )ERC20(_manager){
        require(_baseAsset != address(0), "Pool: invalid clearAnchor");
        require(bytes(_lpTokenName).length != 0, "Pool: invalid lp token name");
        require(bytes(_lpTokenSymbol).length != 0, "Pool: invalid lp token symbol");
        require(_WETH != address(0) && _manager!= address(0), "Pool: invalid address");
        baseAsset = _baseAsset;
        baseAssetDecimals = IERC20(_baseAsset).decimals();
        name = _lpTokenName;
        symbol = _lpTokenSymbol;
        WETH = _WETH;
        vault = IManager(_manager).vault();
        sharePrice = PRICE_PRECISION;
        require(vault != address(0), "Pool: invalid vault in manager");
    }
    modifier _onlyMarket(){
        require(isMarket[msg.sender], 'Pool: not official market');
        _;
    }

    modifier _onlyRouter(){
        require(IManager(manager).checkRouter(msg.sender), 'Pool: only router');
        _;
    }

    modifier whenNotAddPaused() {
        require(!IManager(manager).paused() && !addPaused, "Pool: adding liquidity paused");
        _;
    }

    modifier whenNotRemovePaused() {
        require(!IManager(manager).paused() && !removePaused, "Pool: removing liquidity paused");
        _;
    }

    function registerMarket(
        address _market
    ) external returns (bool){
        require(msg.sender == manager, "Pool: only manage");
        require(!isMarket[_market], "Pool: already registered");
        isMarket[_market] = true;
        marketList.push(_market);
        MarketConfig storage args = marketConfigs[_market];
        args.marketType = IMarket(_market).marketType();
        emit RegisterMarket(_market);
        return true;
    }

    function getOrder(uint256 _id) external view returns (PoolDataStructure.MakerOrder memory){
        return makerOrders[_id];
    }

    /// @notice update pool data when an order with types of open or trigger open is executed
    function openUpdate(IPool.OpenUpdateInternalParams memory params) external _onlyMarket returns (bool){
        address _market = msg.sender;
        require(canOpen(_market, params._makerMargin), "Pool: insufficient pool available balance");
        DataByMarket storage marketData = poolDataByMarkets[_market];
        marketData.takerTotalMargin = marketData.takerTotalMargin.add(params._takerMargin);

        balance = balance.add(params.makerFee);
        marketData.cumulativeFee = marketData.cumulativeFee.add(params.makerFee);
        balance = balance.sub(params._makerMargin);
        interestData[params._takerDirection].totalBorrowShare = interestData[params._takerDirection].totalBorrowShare.add(params.deltaDebtShare);
        if (params._takerDirection == 1) {
            marketData.longMakerFreeze = marketData.longMakerFreeze.add(params._makerMargin);
            marketData.longAmount = marketData.longAmount.add(params._amount);
            marketData.longOpenTotal = marketData.longOpenTotal.add(params._total);
        } else {
            marketData.shortMakerFreeze = marketData.shortMakerFreeze.add(params._makerMargin);
            marketData.shortAmount = marketData.shortAmount.add(params._amount);
            marketData.shortOpenTotal = marketData.shortOpenTotal.add(params._total);
        }

        _marginToVault(params.marginToVault);
        _feeToExchange(params.feeToExchange);
        _transfer(params.inviter, params.feeToInviter, baseAsset == WETH);

        (uint256 _sharePrice,) = getSharePrice();
        emit OpenUpdate(
            params.orderId,
            _market,
            params.taker,
            params.inviter,
            params.feeToExchange,
            params.makerFee,
            params.feeToInviter,
            _sharePrice,
            marketData.shortOpenTotal,
            marketData.longOpenTotal
        );
        return true;
    }

    /// @notice update pool data when an order with types of close or trigger close is executed
    function closeUpdate(IPool.CloseUpdateInternalParams memory params) external _onlyMarket returns (bool){
        address _market = msg.sender;
        DataByMarket storage marketData = poolDataByMarkets[_market];
        marketData.cumulativeFee = marketData.cumulativeFee.add(params.makerFee);
        balance = balance.add(params.makerFee);

        marketData.rlzPNL = marketData.rlzPNL.add(params._makerProfit);
        {
            int256 tempProfit = params._makerProfit.add(params._makerMargin.toInt256()).add(params.fundingPayment);
            require(tempProfit >= 0, 'Pool: tempProfit is invalid');

            balance = tempProfit.add(balance.toInt256()).toUint256().add(params.payInterest);
        }

        require(marketData.takerTotalMargin >= params._takerMargin, 'Pool: takerMargin is invalid');
        marketData.takerTotalMargin = marketData.takerTotalMargin.sub(params._takerMargin);
        interestData[params._takerDirection].totalBorrowShare = interestData[params._takerDirection].totalBorrowShare.sub(params.deltaDebtShare);
        if (params.fundingPayment != 0) marketData.makerFundingPayment = marketData.makerFundingPayment.sub(params.fundingPayment);
        if (params._takerDirection == 1) {
            marketData.longAmount = marketData.longAmount.sub(params._amount);
            marketData.longOpenTotal = marketData.longOpenTotal.sub(params._total);
            marketData.longMakerFreeze = marketData.longMakerFreeze.sub(params._makerMargin);
        } else {
            marketData.shortAmount = marketData.shortAmount.sub(params._amount);
            marketData.shortOpenTotal = marketData.shortOpenTotal.sub(params._total);
            marketData.shortMakerFreeze = marketData.shortMakerFreeze.sub(params._makerMargin);
        }

        _marginToVault(params.marginToVault);
        _feeToExchange(params.feeToExchange);
        _transfer(params.taker, params.toTaker, params.isOutETH);
        _transfer(params.inviter, params.feeToInviter, baseAsset == WETH);
        _transfer(IManager(manager).riskFunding(), params.toRiskFund, false);

        (uint256 _sharePrice,) = getSharePrice();
        emit CloseUpdate(
            params.orderId,
            _market,
            params.taker,
            params.inviter,
            params.feeToExchange,
            params.makerFee,
            params.feeToInviter,
            params.toRiskFund,
            params._makerProfit.neg256(),
            params.fundingPayment,
            params.payInterest,
            _sharePrice,
            marketData.shortOpenTotal,
            marketData.longOpenTotal
        );
        return true;
    }

    function _marginToVault(uint256 _margin) internal {
        if (_margin > 0) IVault(vault).addPoolBalance(_margin);
    }

    function _feeToExchange(uint256 _fee) internal {
        if (_fee > 0) IVault(vault).addExchangeFeeBalance(_fee);
    }

    function _transfer(address _to, uint256 _amount, bool _isOutETH) internal {
        if (_amount > 0) IVault(vault).transfer(_to, _amount, _isOutETH);
    }

    /// @notice pool update when user increasing or decreasing the position margin
    function takerUpdateMargin(address _market, address taker, int256 _margin, bool isOutETH) external _onlyMarket returns (bool){
        require(_margin != 0, 'Pool: delta margin is 0');
        DataByMarket storage marketData = poolDataByMarkets[_market];

        if (_margin > 0) {
            marketData.takerTotalMargin = marketData.takerTotalMargin.add(_margin.toUint256());
            _marginToVault(_margin.toUint256());
        } else {
            marketData.takerTotalMargin = marketData.takerTotalMargin.sub(_margin.neg256().toUint256());
            _transfer(taker, _margin.neg256().toUint256(), isOutETH);
        }
        return true;
    }

    // update liquidity order when add liquidity
    function addLiquidity(
        address sender,
        uint256 amount
    ) external nonReentrant _onlyRouter whenNotAddPaused returns (
        uint256 _id
    ){
        require(sender != address(0), "Pool: sender is address(0)");
        require(amount >= minAddLiquidityAmount, 'Pool: amount < min amount');
        require(block.timestamp > lastOperationTime[sender], "Pool: operate too frequency");
        lastOperationTime[sender] = block.timestamp;

        makerOrders[autoId] = PoolDataStructure.MakerOrder(
            autoId,
            sender,
            block.timestamp,
            amount,
            0,
            0,
            sharePrice,
            0,
            0,
            PoolDataStructure.PoolAction.Deposit,
            PoolDataStructure.PoolActionStatus.Submit
        );
        _id = makerOrders[autoId].id;
        makerOrderIds[sender].push(autoId);
        autoId = autoId.add(1);
    }

    /// @notice execute add liquidity order, update order data, pnl, fundingFee, trader fee, sharePrice, liquidity totalSupply
    /// @param id order id
    function executeAddLiquidityOrder(
        uint256 id
    ) external nonReentrant _onlyRouter returns (uint256 liquidity){
        PoolDataStructure.MakerOrder storage order = makerOrders[id];
        order.status = PoolDataStructure.PoolActionStatus.Success;

        (DataByMarket memory allMarketPos, uint256 allMakerFreeze) = getAllMarketData();
        _updateBorrowIG(allMarketPos.longMakerFreeze, allMarketPos.shortMakerFreeze);
        uint256 poolInterest = getPooInterest(allMarketPos.longMakerFreeze, allMarketPos.shortMakerFreeze);

        int256 totalUnPNL;
        uint256 poolTotalTmp;
        if (balance.add(allMakerFreeze) > 0 && totalSupply > 0) {
            (totalUnPNL) = makerProfitForLiquidity(true);
            require((totalUnPNL.add(allMarketPos.makerFundingPayment).add(poolInterest.toInt256()) <= allMarketPos.takerTotalMargin.toInt256()) && (totalUnPNL.neg256().sub(allMarketPos.makerFundingPayment) <= allMakerFreeze.toInt256()), 'Pool: taker or maker is broken');
            
            poolTotalTmp = calcPoolTotal(balance, allMakerFreeze, totalUnPNL, allMarketPos.makerFundingPayment, poolInterest);
            liquidity = order.amount.mul(totalSupply).div(poolTotalTmp);
        } else {
            liquidity = order.amount.mul(10 ** decimals).div(10 ** baseAssetDecimals);
        }
        _mint(order.maker, liquidity);
        balance = balance.add(order.amount);
        poolTotalTmp = poolTotalTmp.add(order.amount);
        order.poolTotal = poolTotalTmp.toInt256();
        sharePrice = totalSupply > 0 ? calcSharePrice(poolTotalTmp) : PRICE_PRECISION;
        order.profit = allMarketPos.rlzPNL.add(allMarketPos.cumulativeFee.toInt256()).add(totalUnPNL).add(allMarketPos.makerFundingPayment).add(poolInterest.toInt256());
        order.liquidity = liquidity;
        order.sharePrice = sharePrice;

        _marginToVault(order.amount);
        //uint256 orderId, address maker, uint256 amount, uint256 share, uint256 sharePrice
        emit  ExecuteAddLiquidityOrder(id, order.maker, order.amount, liquidity, order.sharePrice);
    }

    function removeLiquidity(
        address sender,
        uint256 liquidity
    ) external nonReentrant _onlyRouter whenNotRemovePaused returns (
        uint256 _id,
        uint256 _liquidity
    ){
        require(sender != address(0), "Pool:removeLiquidity sender is zero address");
        require(liquidity >= minRemoveLiquidityAmount, "Pool: liquidity is less than the minimum limit");

        liquidity = balanceOf[sender] >= liquidity ? liquidity : balanceOf[sender];

        require(block.timestamp > lastOperationTime[sender], "Pool: operate too frequency");
        lastOperationTime[sender] = block.timestamp;

        balanceOf[sender] = balanceOf[sender].sub(liquidity);
        freezeBalanceOf[sender] = freezeBalanceOf[sender].add(liquidity);
        makerOrders[autoId] = PoolDataStructure.MakerOrder(
            autoId,
            sender,
            block.timestamp,
            0,
            liquidity,
            0,
            sharePrice,
            0,
            0,
            PoolDataStructure.PoolAction.Withdraw,
            PoolDataStructure.PoolActionStatus.Submit
        );
        _id = makerOrders[autoId].id;
        _liquidity = makerOrders[autoId].liquidity;
        makerOrderIds[sender].push(autoId);
        autoId = autoId.add(1);
    }

    /// @notice execute remove liquidity order
    /// @param id order id
    function executeRmLiquidityOrder(
        uint256 id,
        bool isETH
    ) external nonReentrant _onlyRouter returns (uint256 amount){
        PoolDataStructure.MakerOrder storage order = makerOrders[id];
        order.status = PoolDataStructure.PoolActionStatus.Success;
        (DataByMarket memory allMarketPos, uint256 allMakerFreeze) = getAllMarketData();
        _updateBorrowIG(allMarketPos.longMakerFreeze, allMarketPos.shortMakerFreeze);
        uint256 poolInterest = getPooInterest(allMarketPos.longMakerFreeze, allMarketPos.shortMakerFreeze);
        int256 totalUnPNL = makerProfitForLiquidity(false);
        require((totalUnPNL.add(allMarketPos.makerFundingPayment).add(poolInterest.toInt256()) <= allMarketPos.takerTotalMargin.toInt256()) && (totalUnPNL.neg256().sub(allMarketPos.makerFundingPayment) <= allMakerFreeze.toInt256()), 'Pool: taker or maker is broken');
        
        uint256 poolTotalTmp = calcPoolTotal(balance, allMakerFreeze, totalUnPNL, allMarketPos.makerFundingPayment, poolInterest);
        amount = order.liquidity.mul(poolTotalTmp).div(totalSupply);

        require(amount > 0, 'Pool: amount error');
        require(balance >= amount, 'Pool: Insufficient balance when remove liquidity');
        balance = balance.sub(amount);
        balanceOf[order.maker] = balanceOf[order.maker].add(order.liquidity);
        freezeBalanceOf[order.maker] = freezeBalanceOf[order.maker].sub(order.liquidity);
        _burn(order.maker, order.liquidity);

        order.amount = amount.mul(RATE_PRECISION.sub(removeLiquidityFeeRate)).div(RATE_PRECISION);
        require(order.amount > 0, 'Pool: amount error');
        order.feeToPool = amount.sub(order.amount);

        if (order.feeToPool > 0) {
            IVault(vault).addPoolRmLpFeeBalance(order.feeToPool);
            cumulateRmLiqFee = cumulateRmLiqFee.add(order.feeToPool);
        }
        poolTotalTmp = poolTotalTmp.sub(amount);
        order.poolTotal = poolTotalTmp.toInt256();
        if (totalSupply > 0) {
            sharePrice = calcSharePrice(poolTotalTmp);
        } else {
            sharePrice = PRICE_PRECISION;
        }
        order.profit = allMarketPos.rlzPNL.add(allMarketPos.cumulativeFee.toInt256()).add(totalUnPNL).add(allMarketPos.makerFundingPayment).add(poolInterest.toInt256());
        order.sharePrice = sharePrice;

        _transfer(order.maker, order.amount, isETH);
        
        emit  ExecuteRmLiquidityOrder(id, order.maker, order.amount, order.liquidity, order.sharePrice, order.feeToPool);
    }

    /// @notice  calculate unrealized pnl of positions in all markets caused by price changes
    /// @param isAdd true: add liquidity or show tvl, false: rm liquidity
    function makerProfitForLiquidity(bool isAdd) public view returns (int256 unPNL){
        for (uint256 i = 0; i < marketList.length; i++) {
            unPNL = unPNL.add(_makerProfitByMarket(marketList[i], isAdd));
        }
    }

    /// @notice calculate unrealized pnl of positions in one single market caused by price changes
    /// @param _market market address
    /// @param _isAdd true: add liquidity or show tvl, false: rm liquidity
    function _makerProfitByMarket(address _market, bool _isAdd) internal view returns (int256 unPNL){
        DataByMarket storage marketData = poolDataByMarkets[_market];
        MarketConfig memory args = marketConfigs[_market];

        int256 shortUnPNL = 0;
        int256 longUnPNL = 0;
        uint256 _price;

        if (_isAdd) {
            _price = getPriceForPool(_market, marketData.longAmount < marketData.shortAmount);
        } else {
            _price = getPriceForPool(_market, marketData.longAmount >= marketData.shortAmount);
        }

        if (args.marketType == 1) {
            int256 closeLongTotal = marketData.longAmount.mul(PRICE_PRECISION).div(_price).toInt256();
            int256 openLongTotal = marketData.longOpenTotal.toInt256();
            longUnPNL = closeLongTotal.sub(openLongTotal);

            int256 closeShortTotal = marketData.shortAmount.mul(PRICE_PRECISION).div(_price).toInt256();
            int256 openShortTotal = marketData.shortOpenTotal.toInt256();
            shortUnPNL = openShortTotal.sub(closeShortTotal);

            unPNL = shortUnPNL.add(longUnPNL);
        } else {
            int256 closeLongTotal = marketData.longAmount.mul(_price).div(PRICE_PRECISION).toInt256();
            int256 openLongTotal = marketData.longOpenTotal.toInt256();
            longUnPNL = openLongTotal.sub(closeLongTotal);

            int256 closeShortTotal = marketData.shortAmount.mul(_price).div(PRICE_PRECISION).toInt256();
            int256 openShortTotal = marketData.shortOpenTotal.toInt256();
            shortUnPNL = closeShortTotal.sub(openShortTotal);

            unPNL = shortUnPNL.add(longUnPNL);
            if (args.marketType == 2) {
                unPNL = unPNL.mul((IMarket(_market).getMarketConfig().multiplier).toInt256()).div(RATE_PRECISION.toInt256());
            }
        }

        unPNL = unPNL.mul((10 ** baseAssetDecimals).toInt256()).div(AMOUNT_PRECISION.toInt256());
    }

    /// @notice calculate and return the share price of a pool
    function getSharePrice() public view returns (
        uint256 _price,
        uint256 _balance
    ){
        (DataByMarket memory allMarketPos, uint256 allMakerFreeze) = getAllMarketData();
        uint256 poolInterest = getPooInterest(allMarketPos.longMakerFreeze, allMarketPos.shortMakerFreeze);
        int totalUnPNL = makerProfitForLiquidity(true);
        if (totalSupply > 0) {
            uint256 poolTotalTmp = calcPoolTotal(balance, allMakerFreeze, totalUnPNL, allMarketPos.makerFundingPayment, poolInterest);
            _price = calcSharePrice(poolTotalTmp);
        } else {
            _price = PRICE_PRECISION;
        }
        _balance = balance;
    }

    /// @notice set minimum amount of base asset to add liquidity
    /// @param _minAmount minimum amount
    function setMinAddLiquidityAmount(uint256 _minAmount) external _onlyController returns (bool){
        minAddLiquidityAmount = _minAmount;
        emit SetMinAddLiquidityAmount(_minAmount);
        return true;
    }

    /// @notice set minimum amount of lp to remove liquidity
    /// @param _minAmount minimum amount
    function setMinRemoveLiquidity(uint256 _minAmount) external _onlyController returns (bool){
        minRemoveLiquidityAmount = _minAmount;
        emit SetMinRemoveLiquidity(_minAmount);
        return true;
    }

    /// @notice set fund utilization limit for markets supported by this pool.
    /// @param _market market address
    /// @param _openRate rate
    /// @param _openLimit limit amount for base asset
    function setOpenRateAndLimit(address _market, uint256 _openRate, uint256 _openLimit) external _onlyController returns (bool){
        MarketConfig storage args = marketConfigs[_market];
        args.fundUtRateLimit = _openRate;
        args.openLimit = _openLimit;
        emit SetOpenRateAndLimit(_market, _openRate, _openLimit);
        return true;
    }

    /// @notice set fund reserve rate for pool
    /// @param _reserveRate reserve rate
    function setReserveRate(uint256 _reserveRate) external _onlyController returns (bool){
        reserveRate = _reserveRate;
        emit SetReserveRate(_reserveRate);
        return true;
    }

    /// @notice set remove lp fee Rate rate
    /// @param _ratio fee _ratio
    function setRemoveLiquidityFeeRatio(uint256 _ratio) external _onlyController returns (bool){
        removeLiquidityFeeRate = _ratio;
        emit SetRemoveLiquidityFeeRatio(_ratio);
        return true;
    }

    /// @notice set paused flags for adding and remove liquidity
    /// @param _add flag for adding liquidity
    /// @param _remove flag for remove liquidity
    function setPaused(bool _add, bool _remove) external _onlyController {
        addPaused = _add;
        removePaused = _remove;
        emit SetPaused(_add, _remove);
    }

    /// @notice set interest logic contract address
    /// @param _interestLogic contract address
    function setInterestLogic(address _interestLogic) external _onlyController {
        require(_interestLogic != address(0), "Pool: invalid interestLogic");
        interestLogic = _interestLogic;
        emit SetInterestLogic(_interestLogic);
    }

    /// @notice set market price feed contract address
    /// @param _marketPriceFeed contract address
    function setMarketPriceFeed(address _marketPriceFeed) external _onlyController {
        require(_marketPriceFeed != address(0), "Pool: invalid marketPriceFeed");
        marketPriceFeed = _marketPriceFeed;
        emit SetMarketPriceFeed(_marketPriceFeed);
    }

    /// @notice get adding or removing liquidity order id list
    /// @param _maker address
    function getMakerOrderIds(address _maker) external view returns (uint256[] memory){
        return makerOrderIds[_maker];
    }

    /// @notice validate whether this open order can be executed
    ///         every market open interest is limited by two params, the open limit and the funding utilization rate limit
    /// @param _market market address
    /// @param _makerMargin margin taken from the pool of this order
    function canOpen(address _market, uint256 _makerMargin) public view returns (bool _can){
        // balance - margin >= (balance + frozen) * reserveRatio
        // => balance >= margin + (balance + frozen) * reserveRatio >= margin
        // when reserve ratio == 0  => balance >= margin

        (,uint256 allMakerFreeze) = getAllMarketData();
        uint256 reserveAmount = balance.add(allMakerFreeze).mul(reserveRate).div(RATE_PRECISION);
        if (balance < reserveAmount.add(_makerMargin)) {
            return false;
        }

        uint256 openLimitFunds = getMarketLimit(_market, allMakerFreeze);
        DataByMarket memory marketData = poolDataByMarkets[_market];
        uint256 marketUsedFunds = marketData.longMakerFreeze.add(marketData.shortMakerFreeze).add(_makerMargin);
        return marketUsedFunds <= openLimitFunds;
    }

    function getLpBalanceOf(address _maker) external view returns (uint256 _balance, uint256 _totalSupply){
        _balance = balanceOf[_maker];
        _totalSupply = totalSupply;
    }

    function updateFundingPayment(address _market, int256 _fundingPayment) external _onlyMarket {
        if (_fundingPayment != 0) {
            DataByMarket storage marketData = poolDataByMarkets[_market];
            marketData.makerFundingPayment = marketData.makerFundingPayment.add(_fundingPayment);
        }
    }

    /// notice update interests global information
    function updateBorrowIG() public {
        (DataByMarket memory allMarketPos,) = getAllMarketData();
        _updateBorrowIG(allMarketPos.longMakerFreeze, allMarketPos.shortMakerFreeze);
    }

    /// @notice update interest index global
    /// @param _longMakerFreeze sum of pool assets taken by the long positions
    /// @param _shortMakerFreeze sum of pool assets taken by the short positions
    function _updateBorrowIG(uint256 _longMakerFreeze, uint256 _shortMakerFreeze) internal {
        (, interestData[1].borrowIG) = _getCurrentBorrowIG(1, _longMakerFreeze, _shortMakerFreeze);
        (, interestData[- 1].borrowIG) = _getCurrentBorrowIG(- 1, _longMakerFreeze, _shortMakerFreeze);
        interestData[1].lastInterestUpdateTs = block.timestamp;
        interestData[- 1].lastInterestUpdateTs = block.timestamp;
    }

    /// @notice get current borrowIG
    /// @param _direction position direction
    function getCurrentBorrowIG(int8 _direction) public view returns (uint256 _borrowRate, uint256 _borrowIG){
        (DataByMarket memory allMarketPos,) = getAllMarketData();
        return _getCurrentBorrowIG(_direction, allMarketPos.longMakerFreeze, allMarketPos.shortMakerFreeze);
    }

    /// @notice calculate the latest interest index global
    /// @param _direction position direction
    /// @param _longMakerFreeze sum of pool assets taken by the long positions
    /// @param _shortMakerFreeze sum of pool assets taken by the short positions
    function _getCurrentBorrowIG(int8 _direction, uint256 _longMakerFreeze, uint256 _shortMakerFreeze) internal view returns (uint256 _borrowRate, uint256 _borrowIG){
        require(_direction == 1 || _direction == - 1, "invalid direction");
        IPool.InterestData memory data = interestData[_direction];

        // calc util need usedBalance,totalBalance,reserveRate
        //(DataByMarket memory allMarketPos, uint256 allMakerFreeze) = getAllMarketData();
        uint256 usedBalance = _direction == 1 ? _longMakerFreeze : _shortMakerFreeze;
        uint256 totalBalance = balance.add(_longMakerFreeze).add(_shortMakerFreeze);

        (_borrowRate, _borrowIG) = IInterestLogic(interestLogic).getMarketBorrowIG(address(this), usedBalance, totalBalance, reserveRate, data.lastInterestUpdateTs, data.borrowIG);
    }

    function getCurrentAmount(int8 _direction, uint256 share) public view returns (uint256){
        (DataByMarket memory allMarketPos,) = getAllMarketData();
        return _getCurrentAmount(_direction, share, allMarketPos.longMakerFreeze, allMarketPos.shortMakerFreeze);
    }

    function _getCurrentAmount(int8 _direction, uint256 share, uint256 _longMakerFreeze, uint256 _shortMakerFreeze) internal view returns (uint256){
        (,uint256 ig) = _getCurrentBorrowIG(_direction, _longMakerFreeze, _shortMakerFreeze);
        return IInterestLogic(interestLogic).getBorrowAmount(share, ig).mul(10 ** baseAssetDecimals).div(AMOUNT_PRECISION);
    }

    function getCurrentShare(int8 _direction, uint256 amount) external view returns (uint256){
        (DataByMarket memory allMarketPos,) = getAllMarketData();
        (,uint256 ig) = _getCurrentBorrowIG(_direction, allMarketPos.longMakerFreeze, allMarketPos.shortMakerFreeze);
        return IInterestLogic(interestLogic).getBorrowShare(amount.mul(AMOUNT_PRECISION).div(10 ** baseAssetDecimals), ig);
    }

    /// @notice get the fund utilization information of a market
    /// @param _market market address
    function getMarketAmount(address _market) external view returns (uint256, uint256, uint256){
        DataByMarket memory marketData = poolDataByMarkets[_market];
        (,uint256 allMakerFreeze) = getAllMarketData();
        uint256 openLimitFunds = getMarketLimit(_market, allMakerFreeze);
        return (marketData.longMakerFreeze, marketData.shortMakerFreeze, openLimitFunds);
    }

    /// @notice calculate the sum data of all markets
    function getAllMarketData() public view returns (DataByMarket memory allMarketPos, uint256 allMakerFreeze){
        for (uint256 i = 0; i < marketList.length; i++) {
            address market = marketList[i];
            DataByMarket memory marketData = poolDataByMarkets[market];

            allMarketPos.rlzPNL = allMarketPos.rlzPNL.add(marketData.rlzPNL);
            allMarketPos.cumulativeFee = allMarketPos.cumulativeFee.add(marketData.cumulativeFee);
            allMarketPos.longMakerFreeze = allMarketPos.longMakerFreeze.add(marketData.longMakerFreeze);
            allMarketPos.shortMakerFreeze = allMarketPos.shortMakerFreeze.add(marketData.shortMakerFreeze);
            allMarketPos.takerTotalMargin = allMarketPos.takerTotalMargin.add(marketData.takerTotalMargin);
            allMarketPos.makerFundingPayment = allMarketPos.makerFundingPayment.add(marketData.makerFundingPayment);
            allMarketPos.longOpenTotal = allMarketPos.longOpenTotal.add(marketData.longOpenTotal);
            allMarketPos.shortOpenTotal = allMarketPos.shortOpenTotal.add(marketData.shortOpenTotal);
        }

        allMakerFreeze = allMarketPos.longMakerFreeze.add(allMarketPos.shortMakerFreeze);
    }

    /// @notice get all assets of this pool including fund available to borrow and taken by positions
    function getAssetAmount() public view returns (uint256 amount){
        (, uint256 allMakerFreeze) = getAllMarketData();
        return balance.add(allMakerFreeze);
    }

    /// @notice get asset of pool
    function getBaseAsset() public view returns (address){
        return baseAsset;
    }

    /// @notice get interest of this pool
    /// @return result the interest principal not included
    function getPooInterest(uint256 _longMakerFreeze, uint256 _shortMakerFreeze) internal view returns (uint256){
        //(DataByMarket memory allMarketPos,) = getAllMarketData();
        uint256 longShare = interestData[1].totalBorrowShare;
        uint256 shortShare = interestData[- 1].totalBorrowShare;
        uint256 longInterest = _getCurrentAmount(1, longShare, _longMakerFreeze, _shortMakerFreeze);
        uint256 shortInterest = _getCurrentAmount(- 1, shortShare, _longMakerFreeze, _shortMakerFreeze);
        longInterest = longInterest <= _longMakerFreeze ? 0 : longInterest.sub(_longMakerFreeze);
        shortInterest = shortInterest <= _shortMakerFreeze ? 0 : shortInterest.sub(_shortMakerFreeze);
        return longInterest.add(shortInterest);
    }

    /// @notice get market open limit
    /// @param _market market address
    /// @return openLimitFunds the max funds used to open
    function getMarketLimit(address _market, uint256 _allMakerFreeze) internal view returns (uint256 openLimitFunds){
        MarketConfig memory args = marketConfigs[_market];
        uint256 availableAmount = balance.add(_allMakerFreeze).mul(RATE_PRECISION.sub(reserveRate)).div(RATE_PRECISION);
        uint256 openLimitByRatio = availableAmount.mul(args.fundUtRateLimit).div(RATE_PRECISION);
        openLimitFunds = openLimitByRatio > args.openLimit ? args.openLimit : openLimitByRatio;
    }

    /// @notice get index price to calculate the pool unrealized pnl
    /// @param _market market address
    /// @param _maximise should maximise the price
    function getPriceForPool(address _market, bool _maximise) internal view returns (uint256){
        return IMarketPriceFeed(marketPriceFeed).priceForPool(IMarket(_market).token(), _maximise);
    }

    /// @notice calc pool total valuation including available balance, margin taken by positions, unPNL, funding and interests
    /// @param _balance balance
    /// @param _allMakerFreeze total margin taken by positions
    /// @param _totalUnPNL total unrealized pnl of all positions
    /// @param _makerFundingPayment total funding payment
    /// @param _poolInterest total interests
    function calcPoolTotal(uint256 _balance, uint256 _allMakerFreeze, int256 _totalUnPNL, int256 _makerFundingPayment, uint256 _poolInterest) internal view returns (uint256){
        return _balance.toInt256()
        .add(_allMakerFreeze.toInt256())
        .add(_totalUnPNL)
        .add(_makerFundingPayment)
        .add(_poolInterest.toInt256())
        .toUint256();
    }

    /// @notice calc share price of lp
    /// @param _totalBalance total valuation of this pool
    function calcSharePrice(uint256 _totalBalance) internal view returns (uint256){
        return _totalBalance
        .mul(10 ** decimals)
        .div(totalSupply)
        .mul(PRICE_PRECISION)
        .div(10 ** baseAssetDecimals);
    }
}

