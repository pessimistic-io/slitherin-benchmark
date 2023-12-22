// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "./MetaContext.sol";
import "./ITrading.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IPairsContract.sol";
import "./IReferrals.sol";
import "./IPosition.sol";
import "./IGovernanceStaking.sol";
import "./IStableVault.sol";
import "./ITradingExtension.sol";
import "./IxTIG.sol";
import "./TradingLibrary.sol";

interface IStable is IERC20 {
    function burnFrom(address account, uint256 amount) external;
    function mintFor(address account, uint256 amount) external;
}

interface ExtendedIERC20 is IERC20 {
    function decimals() external view returns (uint);
}

interface ERC20Permit is IERC20 {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

interface ILPStaking {
    function distribute(address _tigAsset, uint256 _amount) external;
}

contract Trading is MetaContext, ITrading {

    using SafeERC20 for IERC20;

    uint256 private constant DIVISION_CONSTANT = 1e10; // 100%
    uint256 private constant LIQPERCENT = 9e9; // 90%

    IPairsContract private pairsContract;
    IPosition private position;
    IGovernanceStaking private staking;
    ILPStaking private lpstaking;
    ITradingExtension private tradingExtension;
    IxTIG private xtig;

    Fees public openFees = Fees(
        0,
        0,
        0,
        0,
        0
    );
    Fees public closeFees = Fees(
        0,
        0,
        0,
        0,
        0
    );

    uint256 private limitOrderPriceRange = 1e10; // 100%
    uint256 public maxWinPercent;
    uint256 public vaultFundingPercent;
    uint256 public timeDelay;
    uint256 public lpDistribution = 3e9;
    uint256 private minSlPnlDif = 1e7; // 0.1%

    mapping(address => uint256) public keeperFee; // tigAsset => fixed fee
    mapping(uint256 => Delay) private timeDelayPassed; // id => Delay
    mapping(address => bool) private allowedVault;
    mapping(address => address) public proxyApprovals;
    mapping(address => mapping(address => bool)) private tokenApprovals;
    mapping(uint256 => PendingMarketOrderData) public pendingMarketOrders;
    mapping(uint256 => PendingAddToPositionOrderData) public pendingAddToPositionOrders;
    uint256[] public pendingMarketOrdersList;
    uint256[] public pendingAddToPositionOrdersList;
    mapping(uint256 => uint256) private pendingMarketOrdersIndex;
    mapping(uint256 => uint256) private pendingAddToPositionOrdersIndex;
    uint256 private pendingOrdersCount;
    bool private allowSameBlockOrderConfirmation = true;

    // ===== EVENTS =====

    event MarketOrderCreated(
        PendingMarketOrderData orderData
    );

    event AddToPositionOrderCreated(
        PendingAddToPositionOrderData orderData
    );

    event MarketOrderCancelled(
        PendingMarketOrderData orderData
    );

    event AddToPositionOrderCancelled(
        PendingAddToPositionOrderData orderData
    );

    event PositionOpened(
        TradeInfo tradeInfo,
        uint256 orderType,
        uint256 price,
        uint256 id,
        address trader,
        uint256 marginAfterFees,
        uint256 orderId
    );

    event PositionClosed(
        uint256 id,
        uint256 closePrice,
        uint256 percent,
        uint256 payout,
        address trader,
        address executor
    );

    event PositionLiquidated(
        uint256 id,
        uint256 liqPrice,
        address trader,
        address executor
    );

    event LimitOrderExecuted(
        uint256 asset,
        bool direction,
        uint256 openPrice,
        uint256 lev,
        uint256 margin,
        uint256 id,
        address trader,
        address executor
    );

    event UpdateTPSL(
        uint256 id,
        bool isTp,
        uint256 price,
        address trader
    );

    event LimitCancelled(
        uint256 id,
        address trader
    );

    event MarginModified(
        uint256 id,
        uint256 newMargin,
        uint256 newLeverage,
        bool isMarginAdded,
        address trader
    );

    event AddToPosition(
        uint256 id,
        uint256 newMargin,
        uint256 newPrice,
        uint256 addMargin,
        address trader,
        uint256 orderId
    );

    event FeesDistributed(
        address tigAsset,
        uint256 daoFees,
        uint256 burnFees,
        uint256 refFees,
        uint256 botFees,
        address referrer
    );

    constructor(
        address _position,
        address _staking,
        address _pairsContract,
        address _lpstaking,
        address _xtig
    )
    {
        if (
            _position == address(0)
            || _staking == address(0)
            || _pairsContract == address(0)
            || _lpstaking == address(0)
            || _xtig == address(0)
        ) {
            revert BadConstructor();
        }
        position = IPosition(_position);
        staking = IGovernanceStaking(_staking);
        lpstaking = ILPStaking(_lpstaking);
        pairsContract = IPairsContract(_pairsContract);
        xtig = IxTIG(_xtig);
    }

    // ===== END-USER FUNCTIONS =====

    /**
     * @param _tradeInfo Trade info
     * @param _priceData verifiable off-chain price data
     * @param _permitData data and signature needed for token approval
     * @param _trader address the trade is initiated for
     */
    function createMarketOrder(
        TradeInfo memory _tradeInfo,
        PriceData calldata _priceData,
        ERC20PermitData calldata _permitData,
        address _trader
    )
        external
    {
        _validateProxy(_trader);
        _checkVault(_tradeInfo.stableVault, _tradeInfo.marginAsset);
        address _tigAsset = _getStable(_tradeInfo.stableVault);
        _validateTrade(_tradeInfo.asset, _tigAsset, _tradeInfo.margin, _tradeInfo.leverage, 0);
        tradingExtension.setReferral(_tradeInfo.referrer, _trader);
        _handleDeposit(_tigAsset, _tradeInfo.marginAsset, _tradeInfo.margin, _tradeInfo.stableVault, _permitData, _trader);
        bool _isTimestampValid = _priceData.timestamp == block.timestamp && allowSameBlockOrderConfirmation;
        uint256 _marginAfterFees = _tradeInfo.margin - _handleOpenFees(_tradeInfo.asset, _tradeInfo.margin*_tradeInfo.leverage/1e18, _trader, _tigAsset, false, !_isTimestampValid);
        uint256 _orderId;
        unchecked {
            _orderId = ++pendingOrdersCount;
        }
        PendingMarketOrderData memory _order = PendingMarketOrderData(
            _orderId,
            block.timestamp,
            _tradeInfo,
            _tigAsset,
            _marginAfterFees,
            _trader
        );
        pendingMarketOrders[_orderId] = _order;
        pendingMarketOrdersIndex[_orderId] = pendingMarketOrdersList.length;
        pendingMarketOrdersList.push(_orderId);
        emit MarketOrderCreated(_order);
        if (_isTimestampValid) {
            confirmMarketOrder(_orderId, _priceData, false);
        }
    }

    /**
     * @param _orderId Pending order ID
     * @param _priceData verifiable off-chain price data
     * @param _earnKeeperFee whether to earn keeper fee
     */
    function confirmMarketOrder(
        uint256 _orderId,
        PriceData calldata _priceData,
        bool _earnKeeperFee
    )
        public
    {
        if (_earnKeeperFee && msg.sender != tx.origin) revert OnlyEOA();
        PendingMarketOrderData memory _order = pendingMarketOrders[_orderId];
        if (_order.timestamp == 0) revert OrderNotFound();
        if (_priceData.timestamp < _order.timestamp + (allowSameBlockOrderConfirmation ? 0 : 1)) revert OldPriceData();
        uint256 _id = _getCount();
        _checkDelay(_id, true);
        uint8 _isLong = _order.tradeInfo.direction ? 1 : 2;
        (uint256 _price,) = _getVerifiedPrice(_order.tradeInfo.asset, _priceData, _isLong);
        _order.tradeInfo.slPrice = _checkSl(_order.tradeInfo.slPrice, _order.tradeInfo.direction, _price, false);
        address _tigAsset = _getStable(_order.tradeInfo.stableVault);
        if (_earnKeeperFee) {
            _handleTokenMint(_tigAsset, _msgSender(), keeperFee[_tigAsset]);
        }
        _removeOrderFromStorage(false, _orderId);
        IPosition.MintTrade memory _mintTrade = IPosition.MintTrade(
            _order.trader,
            _order.marginAfterFees,
            _order.tradeInfo.leverage,
            _order.tradeInfo.asset,
            _order.tradeInfo.direction,
            _price,
            _order.tradeInfo.tpPrice,
            _order.tradeInfo.slPrice,
            0,
            _tigAsset
        );
        {
            uint256 _positionSize = _order.marginAfterFees * _order.tradeInfo.leverage / 1e18;
            _handleModifyOi(_order.tradeInfo.direction, _order.tradeInfo.asset, _tigAsset, true, _positionSize);
        }
        _updateFunding(_order.tradeInfo.asset, _tigAsset);
        _handlePositionMint(_mintTrade);
        emit PositionOpened(_order.tradeInfo, 0, _price, _id, _order.trader, _order.marginAfterFees, _orderId);
    }

    /**
     * @dev initiate closing position
     * @param _id id of the position NFT
     * @param _percent percent of the position being closed in BP
     * @param _priceData verifiable off-chain price data
     * @param _stableVault StableVault address
     * @param _outputToken Token received upon closing trade
     * @param _trader address the trade is initiated for
     */
    function initiateCloseOrder(
        uint256 _id,
        uint256 _percent,
        PriceData calldata _priceData,
        address _stableVault,
        address _outputToken,
        address _trader
    )
        external
    {
        _validateProxy(_trader);
        _checkDelay(_id, false);
        _checkOwner(_id, _trader);
        _checkVault(_stableVault, _outputToken);
        IPosition.Trade memory _trade = _getTrade(_id);
        if (_trade.orderType != 0) revert IsLimit();
        (uint256 _price,) = _getVerifiedPrice(_trade.asset, _priceData, 0);
        _closePosition(_id, _percent, _price, _stableVault, _outputToken, false);
    }

    /**
     * @param _id position id
     * @param _addMargin margin amount used to add to the position
     * @param _priceData verifiable off-chain price data
     * @param _stableVault StableVault address
     * @param _marginAsset Token being used to add to the position
     * @param _permitData data and signature needed for token approval
     * @param _trader address the trade is initiated for
     */
    function createAddToPositionOrder(
        uint256 _id,
        PriceData calldata _priceData,
        address _stableVault,
        address _marginAsset,
        uint256 _addMargin,
        ERC20PermitData calldata _permitData,
        address _trader
    )
        external
    {
        _validateProxy(_trader);
        _checkOwner(_id, _trader);
        IPosition.Trade memory _trade = _getTrade(_id);
        _validateTrade(_trade.asset, _trade.tigAsset, _trade.margin + _addMargin, _trade.leverage, 0);
        _checkVault(_stableVault, _marginAsset);
        if (_trade.orderType != 0) revert IsLimit();
        bool _isTimestampValid = _priceData.timestamp == block.timestamp && allowSameBlockOrderConfirmation;
        uint256 _fee = _handleOpenFees(_trade.asset, _addMargin*_trade.leverage/1e18, _trader, _trade.tigAsset, false, !_isTimestampValid);
        _handleDeposit(
            _trade.tigAsset,
            _marginAsset,
            _addMargin,
            _stableVault,
            _permitData,
            _trader
        );
        uint256 _orderId;
        unchecked {
            _orderId = ++pendingOrdersCount;
        }
        PendingAddToPositionOrderData memory _order = PendingAddToPositionOrderData(
            _orderId,
            _trade.id,
            _trade.asset,
            block.timestamp,
            _addMargin - _fee,
            _trade.tigAsset,
            _trader
        );
        pendingAddToPositionOrders[_orderId] = _order;
        pendingAddToPositionOrdersIndex[_orderId] = pendingAddToPositionOrdersList.length;
        pendingAddToPositionOrdersList.push(_orderId);
        emit AddToPositionOrderCreated(_order);
        if (_isTimestampValid) {
            confirmAddToPositionOrder(_orderId, _priceData, false);
        }
    }

    /**
     * @param _orderId Pending order ID
     * @param _priceData verifiable off-chain price data
     * @param _earnKeeperFee boolean indicating whether to earn keeper fee
     */
    function confirmAddToPositionOrder(
        uint256 _orderId,
        PriceData calldata _priceData,
        bool _earnKeeperFee
    )
        public
    {
        if (_earnKeeperFee && msg.sender != tx.origin) revert OnlyEOA();
        PendingAddToPositionOrderData memory _order = pendingAddToPositionOrders[_orderId];
        if (_order.timestamp == 0) revert OrderNotFound();
        if (_priceData.timestamp < _order.timestamp + (allowSameBlockOrderConfirmation ? 0 : 1)) revert OldPriceData();
        uint256 _id = _order.tradeId;
        IPosition.Trade memory _trade = _getTrade(_id);
        _checkDelay(_id, true);
        uint8 _isLong = _trade.direction ? 1 : 2;
        (uint256 _price,) = _getVerifiedPrice(_trade.asset, _priceData, _isLong);
        {
            (,int256 _payout) = _getPnl(_trade.direction, _priceData.price, _trade.price, _trade.margin, _trade.leverage, _trade.accInterest);
            if (maxWinPercent != 0 && _payout >= int256(_trade.margin*(maxWinPercent-DIVISION_CONSTANT)/DIVISION_CONSTANT)) revert CloseToMaxPnL();
        }
        position.setAccInterest(_id);
        {
            uint256 _positionSize = _order.marginToAdd * _trade.leverage / 1e18;
            _handleModifyOi(_trade.direction, _trade.asset, _trade.tigAsset, true, _positionSize);
        }
        _updateFunding(_trade.asset, _trade.tigAsset);
        uint256 _newMargin = _trade.margin + _order.marginToAdd;
        uint256 _newPrice = _trade.price * _price * _newMargin /  (_trade.margin * _price + _order.marginToAdd * _trade.price);
        position.addToPosition(
            _trade.id,
            _newMargin,
            _newPrice
        );
        _removeOrderFromStorage(true, _orderId);
        if (_earnKeeperFee) {
            _handleTokenMint(_trade.tigAsset, _msgSender(), keeperFee[_trade.tigAsset]);
        }
        emit AddToPosition(_trade.id, _newMargin, _newPrice, _order.marginToAdd, _trade.trader, _orderId);
    }

    /**
     * @param _tradeInfo Trade info
     * @param _orderType type of limit order used to open the position
     * @param _price limit price
     * @param _permitData data and signature needed for token approval
     * @param _trader address the trade is initiated for
     */
    function initiateLimitOrder(
        TradeInfo calldata _tradeInfo,
        uint256 _orderType, // 1 limit, 2 stop
        uint256 _price,
        ERC20PermitData calldata _permitData,
        address _trader
    )
        external
    {
        _validateProxy(_trader);
        address _tigAsset = _getStable(_tradeInfo.stableVault);
        if (_orderType == 0) revert NotLimit();
        if (_price == 0) revert NoPrice();
        _validateTrade(_tradeInfo.asset, _tigAsset, _tradeInfo.margin, _tradeInfo.leverage, _orderType);
        _checkVault(_tradeInfo.stableVault, _tradeInfo.marginAsset);
        tradingExtension.setReferral(_tradeInfo.referrer, _trader);
        _handleDeposit(_tigAsset, _tradeInfo.marginAsset, _tradeInfo.margin, _tradeInfo.stableVault, _permitData, _trader);
        _checkSl(_tradeInfo.slPrice, _tradeInfo.direction, _price, true);
        uint256 _id = _getCount();
        _checkDelay(_id, false);
        _handlePositionMint(
            IPosition.MintTrade(
                _trader,
                _tradeInfo.margin,
                _tradeInfo.leverage,
                _tradeInfo.asset,
                _tradeInfo.direction,
                _price,
                _tradeInfo.tpPrice,
                _tradeInfo.slPrice,
                _orderType,
                _tigAsset
            )
        );
        emit PositionOpened(_tradeInfo, _orderType, _price, _id, _trader, _tradeInfo.margin, 0);
    }

    /**
     * @param _id position ID
     * @param _trader address the trade is initiated for
     */
    function cancelLimitOrder(
        uint256 _id,
        address _trader
    )
        external
    {
        _validateProxy(_trader);
        _checkOwner(_id, _trader);
        IPosition.Trade memory _trade = _getTrade(_id);
        if (_trade.orderType == 0) revert();
        _handleTokenMint(_trade.tigAsset, _trader, _trade.margin);
        _handlePositionBurn(_id);
        emit LimitCancelled(_id, _trader);
    }

    function cancelPendingOrder(
        bool _isAddToPositionOrder,
        uint256 _orderId
    )
        external
    {
        if (_isAddToPositionOrder) {
            PendingAddToPositionOrderData memory _order = pendingAddToPositionOrders[_orderId];
            if (block.timestamp < _order.timestamp + timeDelay) revert TooEarlyToCancel();
            if (_order.timestamp == 0) revert OrderNotFound();
            _validateProxy(_order.trader);
            _removeOrderFromStorage(true, _orderId);
            _handleTokenMint(_order.tigAsset, _order.trader, _order.marginToAdd);
            emit AddToPositionOrderCancelled(_order);
        } else {
            PendingMarketOrderData memory _order = pendingMarketOrders[_orderId];
            if (block.timestamp < _order.timestamp + timeDelay) revert TooEarlyToCancel();
            if (_order.timestamp == 0) revert OrderNotFound();
            _validateProxy(_order.trader);
            _removeOrderFromStorage(false, _orderId);
            _handleTokenMint(_order.tigAsset, _order.trader, _order.marginAfterFees);
            emit MarketOrderCancelled(_order);
        }
    }

    /**
     * @param _id position id
     * @param _stableVault StableVault address
     * @param _marginAsset Token being used to add to the position
     * @param _addMargin margin amount being added to the position
     * @param _priceData verifiable off-chain price data
     * @param _permitData data and signature needed for token approval
     * @param _trader address the trade is initiated for
     */
    function addMargin(
        uint256 _id,
        address _stableVault,
        address _marginAsset,
        uint256 _addMargin,
        PriceData calldata _priceData,
        ERC20PermitData calldata _permitData,
        address _trader
    )
        external
    {
        _validateProxy(_trader);
        _checkOwner(_id, _trader);
        _checkVault(_stableVault, _marginAsset);
        IPosition.Trade memory _trade = _getTrade(_id);
        _getVerifiedPrice(_trade.asset, _priceData, 0);
        (,int256 _payout) = _getPnl(_trade.direction, _priceData.price, _trade.price, _trade.margin, _trade.leverage, _trade.accInterest);
        if (maxWinPercent != 0 && _payout >= int256(_trade.margin*(maxWinPercent-DIVISION_CONSTANT)/DIVISION_CONSTANT)) revert CloseToMaxPnL();
        if (_trade.orderType != 0) revert IsLimit();
        IPairsContract.Asset memory asset = _getAsset(_trade.asset);
        _handleDeposit(_trade.tigAsset, _marginAsset, _addMargin, _stableVault, _permitData, _trader);
        uint256 _newMargin = _trade.margin + _addMargin;
        uint256 _newLeverage = _trade.margin * _trade.leverage / _newMargin;
        if (_newLeverage < asset.minLeverage) revert BadLeverage();
        position.modifyMargin(_id, _newMargin, _newLeverage);
        emit MarginModified(_id, _newMargin, _newLeverage, true, _trader);
    }

    /**
     * @param _id position id
     * @param _stableVault StableVault address
     * @param _outputToken token the trader will receive
     * @param _removeMargin margin amount being removed from the position
     * @param _priceData verifiable off-chain price data
     * @param _trader address the trade is initiated for
     */
    function removeMargin(
        uint256 _id,
        address _stableVault,
        address _outputToken,
        uint256 _removeMargin,
        PriceData calldata _priceData,
        address _trader
    )
        external
    {
        _validateProxy(_trader);
        _checkOwner(_id, _trader);
        _checkVault(_stableVault, _outputToken);
        IPosition.Trade memory _trade = _getTrade(_id);
        if (_trade.orderType != 0) revert IsLimit();
        (uint256 _assetPrice,) = _getVerifiedPrice(_trade.asset, _priceData, 0);
        (,int256 _payout) = _getPnl(_trade.direction, _assetPrice, _trade.price, _trade.margin, _trade.leverage, _trade.accInterest);
        if (maxWinPercent != 0 && _payout >= int256(_trade.margin*(maxWinPercent-DIVISION_CONSTANT)/DIVISION_CONSTANT)) revert CloseToMaxPnL();
        IPairsContract.Asset memory asset = _getAsset(_trade.asset);
        uint256 _newMargin = _trade.margin - _removeMargin;
        uint256 _newLeverage = _trade.margin * _trade.leverage / _newMargin;
        if (_newLeverage > asset.maxLeverage) revert BadLeverage();
        (,int256 _payoutAfter) = _getPnl(_trade.direction, _assetPrice, _trade.price, _newMargin, _newLeverage, _trade.accInterest);
        if (_payoutAfter <= int256(_newMargin*(DIVISION_CONSTANT-LIQPERCENT)/DIVISION_CONSTANT)) revert LiqThreshold();
        position.modifyMargin(_trade.id, _newMargin, _newLeverage);
        _handleWithdraw(_trade, _stableVault, _outputToken, _removeMargin);
        emit MarginModified(_trade.id, _newMargin, _newLeverage, false, _trader);
    }

    /**
     * @param _type true for TP, false for SL
     * @param _id position id
     * @param _limitPrice TP/SL trigger price
     * @param _priceData verifiable off-chain price data
     * @param _trader address the trade is initiated for
     */
    function updateTpSl(
        bool _type,
        uint256 _id,
        uint256 _limitPrice,
        PriceData calldata _priceData,
        address _trader
    )
        external
    {
        _validateProxy(_trader);
        _checkOwner(_id, _trader);
        _checkDelay(_id, false);
        IPosition.Trade memory _trade = _getTrade(_id);
        if (_trade.orderType != 0) revert IsLimit();
        if (_type) {
            position.modifyTp(_id, _limitPrice);
        } else {
            (uint256 _price,) = _getVerifiedPrice(_trade.asset, _priceData, 0);
            _checkSl(_limitPrice, _trade.direction, _price, true);
            position.modifySl(_id, _limitPrice);
        }
        emit UpdateTPSL(_id, _type, _limitPrice, _trader);
    }

    /**
     * @param _id position id
     * @param _priceData verifiable off-chain price data
     */
    function executeLimitOrder(
        uint256 _id,
        PriceData calldata _priceData
    )
        external
    {
        _checkDelay(_id, true);
        if (tradingExtension.paused()) revert TradingPaused();
        IPosition.Trade memory _trade = _getTrade(_id);
        _trade.margin -= _handleOpenFees(_trade.asset, _trade.margin* _trade.leverage/1e18, _trade.trader, _trade.tigAsset, true, false);
        uint8 _isLong = _trade.direction ? 1 : 2;
        (uint256 _price,) = _getVerifiedPrice(_trade.asset, _priceData, _isLong);
        if (_trade.orderType == 0) revert NotLimit();
        if (_price > _trade.price+ _trade.price*limitOrderPriceRange/DIVISION_CONSTANT || _price < _trade.price- _trade.price*limitOrderPriceRange/DIVISION_CONSTANT) revert LimitNotMet();
        if (_trade.direction && _trade.orderType == 1) {
            if (_trade.price < _price) revert LimitNotMet();
        } else if (!_trade.direction && _trade.orderType == 1) {
            if (_trade.price > _price) revert LimitNotMet();
        } else if (!_trade.direction && _trade.orderType == 2) {
            if (_trade.price < _price) revert LimitNotMet();
            _trade.price = _price;
        } else {
            if (_trade.price > _price) revert LimitNotMet();
            _trade.price = _price;
        }
        _handleModifyOi(_trade.direction, _trade.asset, _trade.tigAsset, true, _trade.margin*_trade.leverage/1e18);
        if (_trade.direction ? _trade.tpPrice <= _trade.price : _trade.tpPrice >= _trade.price) position.modifyTp(_id, 0);
        _updateFunding(_trade.asset, _trade.tigAsset);
        position.executeLimitOrder(_id, _trade.price, _trade.margin);
        emit LimitOrderExecuted(_trade.asset, _trade.direction, _trade.price, _trade.leverage, _trade.margin, _id, _trade.trader, _msgSender());
    }

    /**
     * @notice liquidate position
     * @param _id id of the position NFT
     * @param _priceData verifiable off-chain data
     */
    function liquidatePosition(
        uint256 _id,
        PriceData calldata _priceData
    )
        external
    {
        unchecked {
            IPosition.Trade memory _trade = _getTrade(_id);
            if (_trade.orderType != 0) revert IsLimit();

            (uint256 _price,) = _getVerifiedPrice(_trade.asset, _priceData, 0);
            (uint256 _positionSizeAfterPrice, int256 _payout) = _getPnl(_trade.direction, _price, _trade.price, _trade.margin, _trade.leverage, _trade.accInterest);
            uint256 _positionSize = _trade.margin*_trade.leverage/1e18;
            if (_payout > int256(_trade.margin*(DIVISION_CONSTANT-LIQPERCENT)/DIVISION_CONSTANT)) revert NotLiquidatable();
            _handleModifyOi(_trade.direction, _trade.asset, _trade.tigAsset, false, _positionSize);
            _updateFunding(_trade.asset, _trade.tigAsset);
            _handleCloseFees(_trade.asset, type(uint).max, _trade.tigAsset, _positionSizeAfterPrice, _trade.trader, true);
            _handlePositionBurn(_id);
            emit PositionLiquidated(_id, _price, _trade.trader, _msgSender());
        }
    }

    /**
     * @dev close position at a pre-set price
     * @param _id id of the position NFT
     * @param _tp true if take profit
     * @param _priceData verifiable off-chain price data
     */
    function limitClose(
        uint256 _id,
        bool _tp,
        PriceData calldata _priceData
    )
        external
    {
        _checkDelay(_id, false);
        (uint256 _limitPrice, address _tigAsset) = tradingExtension._limitClose(_id, _tp, _priceData);
        _closePosition(_id, DIVISION_CONSTANT, _limitPrice, address(0), _tigAsset, true);
    }

    /**
     * @notice Trader can approve a proxy wallet address for it to trade on its behalf. Can also provide proxy wallet with gas.
     * @param _proxy proxy wallet address
     */
    function approveProxy(address _proxy) external payable {
        require(_proxy != address(0), "ZeroAddress");
        proxyApprovals[_msgSender()] = _proxy;
        (bool sent,) = payable(_proxy).call{value: msg.value}("");
        require(sent, "F");
    }

    // ===== INTERNAL FUNCTIONS =====

    /**
     * @dev close the initiated position.
     * @param _id id of the position NFT
     * @param _percent percent of the position being closed
     * @param _price pair price
     * @param _stableVault StableVault address
     * @param _outputToken Token that trader will receive
     * @param _isBot false if closed via market order
     */
    function _closePosition(
        uint256 _id,
        uint256 _percent,
        uint256 _price,
        address _stableVault,
        address _outputToken,
        bool _isBot
    )
        internal
    {
        if (_percent > DIVISION_CONSTANT || _percent == 0) revert BadClosePercent();
        IPosition.Trade memory _trade = _getTrade(_id);
        (uint256 _positionSize, int256 _payout) = _getPnl(_trade.direction, _price, _trade.price, _trade.margin, _trade.leverage, _trade.accInterest);
        unchecked {
            _handleModifyOi(_trade.direction, _trade.asset, _trade.tigAsset, false, (_trade.margin*_trade.leverage/1e18)*_percent/DIVISION_CONSTANT);
        }
        position.setAccInterest(_id);
        _updateFunding(_trade.asset, _trade.tigAsset);
        if (_percent < DIVISION_CONSTANT) {
            if ((_trade.margin*_trade.leverage*(DIVISION_CONSTANT-_percent)/DIVISION_CONSTANT)/1e18 < tradingExtension.minPos(_trade.tigAsset)) revert BelowMinPositionSize();
            position.reducePosition(_id, _percent);
        } else {
            _handlePositionBurn(_id);
        }
        uint256 _toMint;
        if (_payout > 0) {
            unchecked {
                _toMint = _handleCloseFees(_trade.asset, uint256(_payout)*_percent/DIVISION_CONSTANT, _trade.tigAsset, _positionSize*_percent/DIVISION_CONSTANT, _trade.trader, _isBot);
                uint256 marginToClose = _trade.margin*_percent/DIVISION_CONSTANT;
                if (maxWinPercent > 0 && _toMint > marginToClose*maxWinPercent/DIVISION_CONSTANT) {
                    _toMint = marginToClose*maxWinPercent/DIVISION_CONSTANT;
                }
            }
            _handleWithdraw(_trade, _stableVault, _outputToken, _toMint);
        }
        emit PositionClosed(_id, _price, _percent, _toMint, _trade.trader, _isBot ? _msgSender() : _trade.trader);
    }

    /**
     * @dev handle stableVault deposits for different trading functions
     * @param _tigAsset tigAsset token address
     * @param _marginAsset token being deposited into stableVault
     * @param _margin amount being deposited
     * @param _stableVault StableVault address
     * @param _permitData Data for approval via permit
     * @param _trader Trader address to take tokens from
     */
    function _handleDeposit(address _tigAsset, address _marginAsset, uint256 _margin, address _stableVault, ERC20PermitData calldata _permitData, address _trader) internal {
        if (_tigAsset != _marginAsset) {
            if (_permitData.usePermit) {
                ERC20Permit(_marginAsset).permit(_trader, address(this), _permitData.amount, _permitData.deadline, _permitData.v, _permitData.r, _permitData.s);
            }
            uint256 _balBefore = _getTokenBalance(_tigAsset, address(this));
            uint256 _marginDecMultiplier = 10**(18-ExtendedIERC20(_marginAsset).decimals());
            IERC20(_marginAsset).safeTransferFrom(_trader, address(this), _margin/_marginDecMultiplier);
            _handleApproval(_marginAsset, _stableVault);
            IStableVault(_stableVault).deposit(_marginAsset, _margin/_marginDecMultiplier);
            uint256 _balAfter = _getTokenBalance(_tigAsset, address(this));
            if (_balAfter != _balBefore + _margin) revert BadDeposit();
            _handleTokenBurn(_tigAsset, address(this), _balAfter);
        } else {
            _handleTokenBurn(_tigAsset, _trader, _margin);
        }
    }

    /**
     * @dev handle stableVault withdrawals for different trading functions
     * @param _trade Position info
     * @param _stableVault StableVault address
     * @param _outputToken Output token address
     * @param _toMint Amount of tigAsset minted to be used for withdrawal
     */
    function _handleWithdraw(IPosition.Trade memory _trade, address _stableVault, address _outputToken, uint256 _toMint) internal {
        _handleTokenMint(_trade.tigAsset, address(this), _toMint);
        uint256 _amountToTransfer = _toMint;
        if (_outputToken != _trade.tigAsset) {
            uint256 _balBefore = _getTokenBalance(_outputToken, address(this));
            IStableVault(_stableVault).withdraw(_outputToken, _toMint);
            uint256 _decimals = ExtendedIERC20(_outputToken).decimals();
            uint256 _balAfter = _getTokenBalance(_outputToken, address(this));
            if (_balAfter != _balBefore + _toMint/(10**(18-_decimals))) revert BadWithdraw();
            _amountToTransfer = _balAfter - _balBefore;
        }
        IERC20(_outputToken).safeTransfer(_trade.trader, _amountToTransfer);
    }

    /**
     * @dev handle fees distribution for opening
     * @param _asset asset id
     * @param _positionSize position size
     * @param _trader trader address
     * @param _tigAsset tigAsset address
     * @param _isBot false if opened via market order
     * @param _useKeeperFee true if keeper fee should be used
     * @return _feePaid total fees paid during opening
     */
    function _handleOpenFees(
        uint256 _asset,
        uint256 _positionSize,
        address _trader,
        address _tigAsset,
        bool _isBot,
        bool _useKeeperFee
    )
        internal
        returns (uint256 _feePaid)
    {
        Fees memory _fees = openFees;
        uint256 _referrerFees;
        if (_useKeeperFee) {
            _fees.keeperFees = keeperFee[_tigAsset];
        }
        (_fees, _referrerFees) = _feesHandling(_fees, _asset, _tigAsset, _positionSize, _trader, _isBot);
        _handleApproval(_tigAsset, address(staking));
        _handleApproval(_tigAsset, address(lpstaking));
        unchecked {
            uint256 _lpDistribution = _fees.daoFees * lpDistribution / DIVISION_CONSTANT;
            lpstaking.distribute(_tigAsset, _lpDistribution);
            staking.distribute(_tigAsset, _fees.daoFees-_lpDistribution);
            _feePaid = _fees.daoFees + _fees.burnFees + _fees.botFees + _referrerFees + _fees.keeperFees;
            xtig.addFees(_trader, _tigAsset, _feePaid);
        }
    }

    /**
     * @dev handle fees distribution for closing
     * @param _asset asset id
     * @param _payout payout to trader before fees
     * @param _tigAsset margin asset
     * @param _positionSize position size
     * @param _trader trader address
     * @param _isBot false if closed via market order
     * @return payout_ payout to trader after fees
     */
    function _handleCloseFees(
        uint256 _asset,
        uint256 _payout,
        address _tigAsset,
        uint256 _positionSize,
        address _trader,
        bool _isBot
    )
        internal
        returns (uint256 payout_)
    {
        (Fees memory _fees, uint256 _referrerFees) = _feesHandling(closeFees, _asset, _tigAsset, _positionSize, _trader, _isBot);
        payout_ = _payout - (_fees.daoFees + _fees.refDiscount) - _fees.burnFees - _fees.botFees;
        unchecked {
            uint256 _lpDistribution = _fees.daoFees * lpDistribution / DIVISION_CONSTANT;
            lpstaking.distribute(_tigAsset, _lpDistribution);
            staking.distribute(_tigAsset, _fees.daoFees-_lpDistribution);
            xtig.addFees(_trader, _tigAsset,
                _fees.daoFees
                + _referrerFees
                + _fees.burnFees
                + _fees.botFees
            );
        }
    }

    /**
     * @dev Handle fee distribution from opening and closing
     * @param _fees fees struct from opening/closing
     * @param _asset asset id
     * @param _tigAsset margin asset
     * @param _positionSize position size
     * @param _trader trader address
     * @param _isBot true if called by a function that is executable by bots (limit orders, liquidations)
     * @return Updated fees struct for further processing
     * @return Fees earned by the referrer
     */
    function _feesHandling(Fees memory _fees, uint256 _asset, address _tigAsset, uint256 _positionSize, address _trader, bool _isBot) internal returns (Fees memory, uint256) {
        IPairsContract.Asset memory asset = _getAsset(_asset);
        (address _referrer, uint256 _referrerFees) = tradingExtension.getRef(_trader);
        unchecked {
            _fees.daoFees = (_positionSize*_fees.daoFees/DIVISION_CONSTANT)*asset.feeMultiplier/DIVISION_CONSTANT
                - _fees.keeperFees;
            _fees.burnFees = (_positionSize*_fees.burnFees/DIVISION_CONSTANT)*asset.feeMultiplier/DIVISION_CONSTANT;
            _fees.botFees = (_positionSize*_fees.botFees/DIVISION_CONSTANT)*asset.feeMultiplier/DIVISION_CONSTANT;
            _fees.refDiscount = (_positionSize*_fees.refDiscount/DIVISION_CONSTANT)*asset.feeMultiplier/DIVISION_CONSTANT;
            _referrerFees = (_positionSize*_referrerFees/DIVISION_CONSTANT)*asset.feeMultiplier/DIVISION_CONSTANT;
        }
        if (_referrer != address(0)) {
            _handleTokenMint(_tigAsset, _referrer, _referrerFees);
            _fees.daoFees = _fees.daoFees-_fees.refDiscount-_referrerFees;
            tradingExtension.addRefFees(_referrer, _tigAsset, _referrerFees);
        } else {
            _referrerFees = 0;
            _fees.refDiscount = 0;
        }
        if (_isBot) {
            _handleTokenMint(_tigAsset, _msgSender(), _fees.botFees);
            _fees.daoFees = _fees.daoFees - _fees.botFees;
        } else {
            _fees.botFees = 0;
        }
        emit FeesDistributed(_tigAsset, _fees.daoFees, _fees.burnFees, _referrerFees, _fees.botFees, _referrer);
        _handleTokenMint(_tigAsset, address(this), _fees.daoFees);
        return (_fees, _referrerFees);
    }

    /**
     * @dev Checks if trade parameters are valid
     * @param _asset asset id
     * @param _tigAsset margin asset
     * @param _margin margin amount
     * @param _leverage leverage amount
     * @param _orderType order type, 0 is market, 1 is limit buy/sell, 2 is buy/sell stop
     */
    function _validateTrade(
        uint256 _asset,
        address _tigAsset,
        uint256 _margin,
        uint256 _leverage,
        uint256 _orderType
    ) internal view {
        tradingExtension.validateTrade(
            _asset,
            _tigAsset,
            _margin,
            _leverage,
            _orderType
        );
    }

    /**
     * @dev Approves a token only once
     * @param _token token address
     * @param _to spender address
     */
    function _handleApproval(address _token, address _to) internal {
        if (!tokenApprovals[_token][_to]) {
            IERC20(_token).approve(_to, type(uint256).max);
            tokenApprovals[_token][_to] = true;
        }
    }

    /**
     * @dev Changes a pair's open interest in pairs contract
     * @param _isLong true if long, false if short
     * @param _asset asset id
     * @param _tigAsset tigAsset used for margin
     * @param _onOpen true if opening, false if closing
     * @param _size position size
     */
    function _handleModifyOi(
        bool _isLong,
        uint256 _asset,
        address _tigAsset,
        bool _onOpen,
        uint256 _size
    ) internal {
        if (_isLong) {
            pairsContract.modifyLongOi(_asset, _tigAsset, _onOpen, _size);
        } else {
            pairsContract.modifyShortOi(_asset, _tigAsset, _onOpen, _size);
        }
    }

    /**
     * @dev Verify price data
     * @param _asset asset id
     * @param _priceData price data struct
     * @param _withSpreadIsLong true if long, false if short
     * @return _price price, 18 decimals
     * @return _spread spread percent, 10 decimals
     */
    function _getVerifiedPrice(
        uint256 _asset,
        PriceData calldata _priceData,
        uint8 _withSpreadIsLong
    ) internal returns (uint256, uint256) {
        return tradingExtension.getVerifiedPrice(_asset, _priceData, _withSpreadIsLong);
    }

    /**
     * @dev Calculate pnl for a position, all integer values 18 decimals
     * @param _direction position direction
     * @param _currentPrice current price
     * @param _openPrice open price
     * @param _margin margin
     * @param _leverage leverage
     * @param _accInterest accumulated interest, negative is interest paid, positive is interest received
     * @return _positionSize position size
     * @return _payout payout
     */
    function _getPnl(
        bool _direction,
        uint256 _currentPrice,
        uint256 _openPrice,
        uint256 _margin,
        uint256 _leverage,
        int256 _accInterest
    ) internal pure returns (uint256 _positionSize, int256 _payout) {
        (_positionSize, _payout) = TradingLibrary.pnl(
            _direction,
            _currentPrice,
            _openPrice,
            _margin,
            _leverage,
            _accInterest
        );
    }

    /**
     * @dev Remove an order from order list and index mapping
     * @param _isAddToPositionOrder is order from add to position or market order
     * @param _orderId order id
     */
    function _removeOrderFromStorage(bool _isAddToPositionOrder, uint256 _orderId) internal {
        if (_isAddToPositionOrder) {
            delete pendingAddToPositionOrders[_orderId];
            TradingLibrary.removeFromStorageArray(_orderId, pendingAddToPositionOrdersList, pendingAddToPositionOrdersIndex);
        } else {
            delete pendingMarketOrders[_orderId];
            TradingLibrary.removeFromStorageArray(_orderId, pendingMarketOrdersList, pendingMarketOrdersIndex);
        }
    }

    /**
     * @dev update funding rates after open interest changes
     * @param _asset asset id
     * @param _tigAsset tigAsset used for OI
     */
    function _updateFunding(uint256 _asset, address _tigAsset) internal {
        IPairsContract.OpenInterest memory _oi = pairsContract.idToOi(_asset, _tigAsset);
        IPairsContract.Asset memory _assetData = _getAsset(_asset);
        position.updateFunding(
            _asset,
            _tigAsset,
            _oi.longOi,
            _oi.shortOi,
            _assetData.baseFundingRate,
            vaultFundingPercent
        );
    }

    /**
     * @dev check that SL price is valid compared to market price
     * @param _sl SL price
     * @param _direction long/short
     * @param _price market price
     * @param _doRevert should revert if SL is invalid
     */
    function _checkSl(uint256 _sl, bool _direction, uint256 _price, bool _doRevert) internal view returns (uint256) {
        if (_direction) {
            if (_sl > _price-_price*minSlPnlDif/DIVISION_CONSTANT) {
                if (_doRevert) {
                    revert BadStopLoss();
                } else {
                    return 0;
                }
            }
        } else {
            if (_sl < _price+_price*minSlPnlDif/DIVISION_CONSTANT && _sl != 0) {
                if (_doRevert) {
                    revert BadStopLoss();
                } else {
                    return 0;
                }
            }
        }
        return _sl;
    }

    /**
     * @dev check that trader address owns the position
     * @param _id position id
     * @param _trader trader address
     */
    function _checkOwner(uint256 _id, address _trader) internal view {
        if (position.ownerOf(_id) != _trader) revert NotOwner();
    }

    /**
     * @dev Get the upcoming position nft index
     */
    function _getCount() internal view returns (uint256) {
        return position.getCount();
    }

    /**
     * @dev Mint a position
     * @param _mintTrade mint trade data
     */
    function _handlePositionMint(IPosition.MintTrade memory _mintTrade) internal {
        position.mint(_mintTrade);
    }

    /**
     * @dev Burn a position
     * @param _id position id
     */
    function _handlePositionBurn(uint256 _id) internal {
        position.burn(_id);
    }

    /**
     * @dev Mint tokens for an account
     * @param _token token address
     * @param _to account address
     * @param _amount amount to mint
     */
    function _handleTokenMint(address _token, address _to, uint256 _amount) internal {
        IStable(_token).mintFor(_to, _amount);
    }

    /**
     * @dev Burn tokens from an account
     * @param _token token address
     * @param _from account address
     * @param _amount amount to burn
     */
    function _handleTokenBurn(address _token, address _from, uint256 _amount) internal {
        IStable(_token).burnFrom(_from, _amount);
    }

    /**
     * @dev Get the token balance of an account
     * @param _token token address
     * @param _account account address
     */
    function _getTokenBalance(address _token, address _account) internal view returns (uint256) {
        return IERC20(_token).balanceOf(_account);
    }

    /**
     * @dev Get the trade data from the position contract
     * @param _id position id
     */
    function _getTrade(uint256 _id) internal view returns (IPosition.Trade memory) {
        return position.trades(_id);
    }

    /**
     * @dev Get the tigAsset address from a stableVault address, which should have the minter role for the tigAsset
     * @param _stableVault stableVault address
     */
    function _getStable(address _stableVault) internal view returns (address) {
        return IStableVault(_stableVault).stable();
    }

    /**
     * @dev Get the pair data from the pairs contract
     * @param _asset pair index
     */
    function _getAsset(uint256 _asset) internal view returns (IPairsContract.Asset memory) {
        return pairsContract.idToAsset(_asset);
    }

    /**
     * @notice Check that sufficient time has passed between opening and closing
     * @dev This is to prevent profitable opening and closing in the same tx with two different prices in the "valid signature pool".
     * @param _id position id
     * @param _type true for opening, false for closing
     */
    function _checkDelay(uint256 _id, bool _type) internal {
        unchecked {
            Delay memory _delay = timeDelayPassed[_id];
            if (_delay.actionType == _type) {
                timeDelayPassed[_id].delay = block.timestamp + timeDelay;
            } else {
                if (block.timestamp < _delay.delay) revert WaitDelay();
                timeDelayPassed[_id].delay = block.timestamp + timeDelay;
                timeDelayPassed[_id].actionType = _type;
            }
        }
    }

    /**
     * @dev Check that the stableVault input is whitelisted and the margin asset is whitelisted in the vault
     * @param _stableVault StableVault address
     * @param _token Margin asset token address
     */
    function _checkVault(address _stableVault, address _token) internal view {
        if (!allowedVault[_stableVault]) revert NotVault();
        if (_token != _getStable(_stableVault) && !IStableVault(_stableVault).allowed(_token)) revert NotAllowedInVault();
    }

    /**
     * @dev Check that the trader has approved the proxy address to trade for it
     * @param _trader Trader address
     */
    function _validateProxy(address _trader) internal view {
        if (_trader != _msgSender()) {
            address _proxy = proxyApprovals[_trader];
            if (_proxy != _msgSender()) revert NotProxy();
        }
    }

    // ===== GOVERNANCE-ONLY =====

    /**
     * @dev Sets timestamp delay between opening and closing
     * @notice payable to reduce contract size, keep value as 0
     * @param _timeDelay delay amount
     */
    function setTimeDelay(
        uint256 _timeDelay
    )
        external payable
        onlyOwner
    {
        timeDelay = _timeDelay;
    }

    /**
     * @dev Whitelists a stableVault contract address
     * @param _stableVault StableVault address
     * @param _bool true if allowed
     */
    function setAllowedVault(
        address _stableVault,
        bool _bool
    )
        external payable
        onlyOwner
    {
        allowedVault[_stableVault] = _bool;
    }

    /**
     * @dev Sets max payout % compared to margin, minimum +500% PnL
     * @param _maxWinPercent payout %
     */
    function setMaxWinPercent(
        uint256 _maxWinPercent
    )
        external payable
        onlyOwner
    {
        unchecked {
            if (_maxWinPercent != 0 && _maxWinPercent < 6*DIVISION_CONSTANT) revert BadSetter();
        }
        maxWinPercent = _maxWinPercent;
    }

    /**
     * @dev Sets executable price range for limit orders
     * @param _range price range in %
     */
    function setLimitOrderPriceRange(uint256 _range) external payable onlyOwner {
        if (_range > DIVISION_CONSTANT) revert BadSetter();
        limitOrderPriceRange = _range;
    }

    /**
     * @dev Sets the percent of fees being distributed to LPs
     * @param _percent Percent 1e10 precision
     */
    function setLPDistribution(uint256 _percent) external payable onlyOwner {
        if (_percent > DIVISION_CONSTANT) revert BadSetter();
        lpDistribution = _percent;
    }

    /**
     * @dev Sets the min pnl difference to set SL
     * @param _percent Percent 1e10 precision
     */
    function setMinSlPnlDif(uint256 _percent) external payable onlyOwner {
        if (_percent > DIVISION_CONSTANT) revert BadSetter();
        minSlPnlDif = _percent;
    }

    /**
     * @dev Sets the fees for the trading protocol
     * @param _open True if open fees are being set
     * @param _daoFees Fees distributed to the DAO
     * @param _burnFees Fees which get burned
     * @param _refDiscount Discount given to referred traders
     * @param _botFees Fees given to bots that execute limit orders
     * @param _percent Percent of earned funding fees going to StableVault
     */
    function setFees(bool _open, uint256 _daoFees, uint256 _burnFees, uint256 _refDiscount, uint256 _botFees, uint256 _percent) external payable onlyOwner {
        if (_open) {
            openFees.daoFees = _daoFees;
            openFees.burnFees = _burnFees;
            openFees.refDiscount = _refDiscount;
            openFees.botFees = _botFees;
        } else {
            closeFees.daoFees = _daoFees;
            closeFees.burnFees = _burnFees;
            closeFees.refDiscount = _refDiscount;
            closeFees.botFees = _botFees;
        }
        if (_percent > DIVISION_CONSTANT) revert BadSetter();
        vaultFundingPercent = _percent;
    }

    /**
     * @dev Sets the keeper fee for a tigAsset
     * @param _tigAsset tigAsset address
     * @param _fee fee amount
     */
    function setKeeperFee(address _tigAsset, uint256 _fee) external payable onlyOwner {
        keeperFee[_tigAsset] = _fee;
    }

    /**
     * @dev Sets the extension contract address for trading
     * @param _ext extension contract address
     */
    function setTradingExtension(
        address _ext
    ) external payable onlyOwner() {
        if (_ext == address(0)) revert BadSetter();
        tradingExtension = ITradingExtension(_ext);
    }

    /**
     * @dev Sets the LP staking contract
     * @param _lpstaking LP staking contract address
     */
    function setLPStaking(
        address _lpstaking
    ) external payable onlyOwner() {
        if (_lpstaking == address(0)) revert BadSetter();
        lpstaking = ILPStaking(_lpstaking);
    }

    /**
     * @dev Sets the pairs contract
     * @param _pairsContract pairs contract address
     */
    function setPairsContract(
        address _pairsContract
    ) external payable onlyOwner() {
        if (_pairsContract == address(0)) revert BadSetter();
        pairsContract = IPairsContract(_pairsContract);
    }

    /**
     * @dev Set if an order can be executed in the same timestamp as it was created
     * @param _allowed True if allowed
     */
    function setAllowSameBlockOrderConfirmation(
        bool _allowed
    ) external payable onlyOwner() {
        allowSameBlockOrderConfirmation = _allowed;
    }

    /**
     * @dev Get the lists of all pending orders
     */
    function getAllOrderIds() external view returns (uint256[] memory _marketOrders, uint256[] memory _addToPositionOrders) {
        return (pendingMarketOrdersList, pendingAddToPositionOrdersList);
    }
}

