// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./UUPSUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

import "./BaseExecutorV2.sol";
import "./IPriceManager.sol";
import "./ITriggerOrderManagerV2.sol";
import "./IPositionRouterV2.sol";
import "./ISettingsManagerV2.sol";
import "./IPositionHandlerV2.sol";
import "./IPositionKeeperV2.sol";
import "./IVaultV2.sol";
import "./IVaultUtilsV2.sol";


import {PositionConstants} from "./PositionConstants.sol";
import {Position, OrderInfo, OrderStatus, OrderType, DataType} from "./Structs.sol";

contract PositionHandlerV2 is PositionConstants, IPositionHandlerV2, BaseExecutorV2, 
        UUPSUpgradeable, ReentrancyGuardUpgradeable {
    mapping(bytes32 => bool) private processing;

    IPriceManager public priceManager;
    ISettingsManagerV2 public settingsManager;
    ITriggerOrderManagerV2 public triggerOrderManager;
    IVaultV2 public vault;
    IVaultUtilsV2 public vaultUtils;
    IPositionKeeperV2 public positionKeeper;
    IPositionRouterV2 public positionRouter;
    uint256[50] private __gap;

    event FinalInitialized(
        address priceManager,
        address settingsManager,
        address triggerOrderManager,
        address vault,
        address vaultUtils,
        address positionRouter,
        address positionKeeper
    );
    event SyncPriceOutdated(bytes32 key, uint256 txType, address[] path);

    modifier notInProcess(bytes32 key) {
        require(!processing[key], "InP"); //In processing
        processing[key] = true;
        _;
        processing[key] = false;
    }

    function initialize(
        address _priceManager,
        address _settingsManager
    ) public reinitializer(4) {
        require(AddressUpgradeable.isContract(_priceManager)
            && AddressUpgradeable.isContract(_settingsManager), "IVLCA");
        super.initialize();
        priceManager = IPriceManager(_priceManager);
        settingsManager = ISettingsManagerV2(_settingsManager);
    }

    function finalInitialize(
        address _triggerOrderManager,
        address _vault,
        address _vaultUtils,
        address _positionRouter,
        address _positionKeeper
    ) public onlyOwner {
        require(AddressUpgradeable.isContract(_triggerOrderManager)
            && AddressUpgradeable.isContract(_vault)
            && AddressUpgradeable.isContract(_vaultUtils)
            && AddressUpgradeable.isContract(_positionRouter)
            && AddressUpgradeable.isContract(_positionKeeper), "IVLCA"); //Invalid contract address
        triggerOrderManager = ITriggerOrderManagerV2(_triggerOrderManager);
        vault = IVaultV2(_vault);
        vaultUtils = IVaultUtilsV2(_vaultUtils);
        positionRouter = IPositionRouterV2(_positionRouter);
        positionKeeper = IPositionKeeperV2(_positionKeeper);
        emit FinalInitialized(
            address(priceManager),
            address(settingsManager),
            _triggerOrderManager,
            _vault,
            _vaultUtils,
            _positionRouter,
            _positionKeeper
        );
    } 

    function _authorizeUpgrade(address) internal override onlyOwner {
        
    }

    function modifyPosition(
        bytes32 _key,
        uint256 _txType, 
        address[] memory _path,
        uint256[] memory _prices,
        bytes memory _data
    ) external notInProcess(_key) {
        require(msg.sender == address(positionRouter), "FBD");
        
        if (_txType != CANCEL_PENDING_ORDER) {
            require(_path.length == _prices.length && _path.length > 0, "IVLARL"); //Invalid array length
        }

        address account;
        bool isFastExecute;
        uint256 delayPositionTxType;

        if (_isOpenPosition(_txType)) {
            //bool isFastExecute;
            (account, isFastExecute) = _openNewPosition(
                _key,
                _path,
                _prices,
                _data
            );
        } else if (_txType == ADD_COLLATERAL || _txType == REMOVE_COLLATERAL) {
            (uint256 amountIn, Position memory position) = abi.decode(_data, ((uint256), (Position)));
            account = position.owner;
            _addOrRemoveCollateral(
                _key, 
                _txType, 
                amountIn, 
                _path, 
                _prices, 
                position
            );
        } else if (_txType == ADD_TRAILING_STOP) {
            bool isLong;
            uint256[] memory params;
            OrderInfo memory order;

            {
                (account, isLong, params, order) = abi.decode(_data, ((address), (bool), (uint256[]), (OrderInfo)));
                _addTrailingStop(_key, isLong, params, order, _getFirstParams(_prices));
            }
        } else if (_txType == UPDATE_TRAILING_STOP) {
            bool isLong;
            OrderInfo memory order;

            {
                (account, isLong, order) = abi.decode(_data, ((address), (bool), (OrderInfo)));
                _updateTrailingStop(_key, isLong, _getFirstParams(_prices), order);
            }
        } else if (_txType == CANCEL_PENDING_ORDER) {
            OrderInfo memory order;
            
            {
                (account, order) = abi.decode(_data, ((address), (OrderInfo)));
                _cancelPendingOrder(_key, order);
            } 
        } else if (_txType == CLOSE_POSITION) {
            (uint256 sizeDelta, Position memory position) = abi.decode(_data, ((uint256), (Position)));
            require(sizeDelta > 0 && sizeDelta <= position.size, "IVLPSD"); //Invalid position size delta
            account = position.owner;
            _decreasePosition(
                _key,
                sizeDelta,
                _getLastPath(_path),
                _getFirstParams(_prices),
                _getLastParams(_prices),
                position
            );
        } else if (_txType == TRIGGER_POSITION) {
            (Position memory position, OrderInfo memory order) = abi.decode(_data, ((Position), (OrderInfo)));
            delayPositionTxType = position.size == 0 ? _getTxTypeFromPositionType(order.positionType) : 0;
            account = position.owner;
            _triggerPosition(
                _key,
                _getLastPath(_path),
                _getFirstParams(_prices),
                _getLastParams(_prices),
                position,
                order
            );
            account = position.owner;
        } else if (_txType == ADD_POSITION) {
            (
                uint256 pendingCollateral, 
                uint256 pendingSize, 
                Position memory position
            ) = abi.decode(_data, ((uint256), (uint256), (Position)));
            account = position.owner;
            _confirmDelayTransaction(
                _key,
                _getLastPath(_path),
                pendingCollateral,
                pendingSize,
                _getFirstParams(_prices),
                _getLastParams(_prices),
                position
            );
        } else if (_txType == LIQUIDATE_POSITION) {
            (Position memory position) = abi.decode(_data, (Position));
            account = position.owner;
            _liquidatePosition(
                _key,
                _getLastPath(_path),
                _getFirstParams(_prices),
                _getLastParams(_prices),
                position
            );
        } else if (_txType == REVERT_EXECUTE) {
            (uint256 originalTxType, Position memory position) = abi.decode(_data, ((uint256), (Position)));
            account = position.owner;

            if (originalTxType == CREATE_POSITION_MARKET && position.size == 0) {
                positionKeeper.deletePositions(_key);
            } else if (originalTxType == ADD_TRAILING_STOP || 
                    originalTxType == ADD_COLLATERAL || 
                    _isDelayPosition(originalTxType)) {
                positionKeeper.deleteOrder(_key);
            }
        } else {
            revert("IVLTXT"); //Invalid txType
        }

        //Reduce vault bond
        if (_txType == ADD_COLLATERAL || _txType == ADD_POSITION 
                || (_txType == TRIGGER_POSITION && delayPositionTxType > 0)
                || (_txType == CREATE_POSITION_MARKET && isFastExecute)) {
            vault.decreaseBond(_key, account, delayPositionTxType > 0 ? delayPositionTxType : _txType);
        }
    }

    function _openNewPosition(
        bytes32 _key,
        address[] memory _path,
        uint256[] memory _prices, 
        bytes memory _data
    ) internal returns (address, bool) {
        bool isFastExecute;
        bool isNewPosition;
        uint256[] memory params;
        Position memory position;
        OrderInfo memory order;
        
        {
            (isFastExecute, isNewPosition, params, position, order) = _validateAndDecodePositionData(
                _getFirstParams(_prices),
                _path,
                _data
            );
        }

        //Only fast execute if position is market
        bool isFastMarketExecute = order.positionType == POSITION_MARKET && isFastExecute;

        if (isFastMarketExecute) {
            _increaseMarketPosition(
                _key,
                _path,
                _prices, 
                position,
                order
            );
        }

        if (isNewPosition) {
            positionKeeper.openNewPosition(
                _key,
                position.isLong,
                position.posId,
                _path,
                params, 
                isFastMarketExecute ? abi.encode(order) : abi.encode(position, order)
            );
        }

        return (position.owner, isFastExecute);
    }

    function _increaseMarketPosition(
        bytes32 _key,
        address[] memory _path,
        uint256[] memory _prices, 
        Position memory _position,
        OrderInfo memory _order
    ) internal {
        require(_order.pendingCollateral > 0 && _order.pendingSize > 0, "IVLPC"); //Invalid pendingCollateral
        uint256 collateralDecimals = priceManager.getTokenDecimals(_getLastPath(_path));
        require(collateralDecimals > 0, "IVLD"); //Invalid decimals
        uint256 pendingCollateral = _order.pendingCollateral;
        uint256 pendingSize = _order.pendingSize;
        _order.pendingCollateral = 0;
        _order.pendingSize = 0;
        _order.collateralToken = address(0);
        _order.status = OrderStatus.FILLED;
        uint256 collateralPrice = _getLastParams(_prices);
        pendingCollateral = _fromTokenToUSD(pendingCollateral, collateralPrice, collateralDecimals);
        pendingSize = _fromTokenToUSD(pendingSize, collateralPrice, collateralDecimals);
        require(pendingCollateral > 0 && pendingSize > 0, "IVLPC"); //Invalid pendingCollateral
        _increasePosition(
            _key,
            pendingCollateral,
            pendingSize,
            _getLastPath(_path),
            _getFirstParams(_prices),
            _position
        );
    }

    /*
    @dev: Set price and execute in batch, temporarily disabled, implement later
    */
    function setPriceAndExecuteInBatch(
        address[] memory _tokens,
        uint256[] memory _prices,
        bytes32[] memory _keys, 
        uint256[] memory _txTypes
    ) external {
        require(_keys.length == _txTypes.length && _keys.length > 0, "IVLARL"); //Invalid array length
        priceManager.setLatestPrices(_tokens, _prices);
        _validateExecutor(msg.sender);

        for (uint256 i = 0; i < _keys.length; i++) {
            address[] memory path = positionRouter.getExecutePath(_keys[i], _txTypes[i]);

            if (path.length > 0) {
                (uint256[] memory prices, bool isLastestSync) = priceManager.getLatestSynchronizedPrices(path);

                if (isLastestSync && !processing[_keys[i]]) {
                    try positionRouter.execute(_keys[i], _txTypes[i], prices) {}
                    catch (bytes memory err) {
                        positionRouter.revertExecution(
                            _keys[i],
                            _txTypes[i],
                            path,
                            prices,
                            _getRevertMsg(err)
                        );
                    }
                } else {
                    emit SyncPriceOutdated(_keys[i], _txTypes[i], path);
                }
            }
        }
    }

    function forceClosePosition(bytes32 _key, uint256[] memory _prices) external {
        _validateExecutor(msg.sender);
        _validatePositionKeeper();
        _validateVaultUtils();
        _validateRouter();
        Position memory position = positionKeeper.getPosition(_key);
        require(position.owner != address(0), "IVLPO"); //Invalid positionOwner
        address[] memory path = positionKeeper.getPositionFinalPath(_key);
        require(path.length > 0 && path.length == _prices.length, "IVLAL"); //Invalid array length
        (bool hasProfit, uint256 pnl, , ) = vaultUtils.calculatePnl(
            position.size,
            position.size - position.collateral,
            _getFirstParams(_prices),
            true,
            true,
            true,
            false,
            position
        );
        require(
            hasProfit && pnl >= (vault.getTotalUSD() * settingsManager.maxProfitPercent()) / BASIS_POINTS_DIVISOR,
            "Not allowed"
        );

        _decreasePosition(
            _key,
            position.size,
            _getLastPath(path),
            _getFirstParams(_prices),
            _getLastParams(_prices),
            position
        );
    }

    function _addOrRemoveCollateral(
        bytes32 _key,
        uint256 _txType,
        uint256 _amountIn,
        address[] memory _path,
        uint256[] memory _prices,
        Position memory _position
    ) internal {
        uint256 prevCollateral = _position.collateral;
        uint256 amountInUSD;
        (amountInUSD, _position) = vaultUtils.validateAddOrRemoveCollateral(
            _amountIn,
            _txType == ADD_COLLATERAL ? true : false,
            _getLastPath(_path), //collateralToken
            _getFirstParams(_prices), //indexPrice
            _getLastParams(_prices), //collateralPrice
            _position
        );
        require(amountInUSD > 0, "IVLAM/Z"); //Invalid amount/zero
        positionKeeper.unpackAndStorage(_key, abi.encode(_position), DataType.POSITION);

        if (_txType == ADD_COLLATERAL) {
            vault.increasePoolAmount(_getLastPath(_path), amountInUSD);
            vault.decreaseGuaranteedAmount(_getLastPath(_path), _position.collateral - prevCollateral);
        } else {
            vault.takeAssetOut(
                _key,
                _position.owner, 
                0, //Zero fee for removeCollateral
                _amountIn, 
                _getLastPath(_path), 
                _getLastParams(_prices)
            );

            vault.decreasePoolAmount(_getLastPath(_path), amountInUSD);
            vault.increaseGuaranteedAmount(_getLastPath(_path), prevCollateral - _position.collateral);
        }

        positionKeeper.emitAddOrRemoveCollateralEvent(
            _key, 
            _txType == ADD_COLLATERAL, 
            _amountIn,
            amountInUSD,
            _position.reserveAmount, 
            _position.collateral, 
            _position.size
        );
    }

    function _addTrailingStop(
        bytes32 _key,
        bool _isLong,
        uint256[] memory _params,
        OrderInfo memory _order,
        uint256 _indexPrice
    ) internal {
        require(positionKeeper.getPositionSize(_key) > 0, "IVLPSZ"); //Invalid position size
        vaultUtils.validateTrailingStopInputData(_key, _isLong, _params, _indexPrice);
        _order.pendingCollateral = _getFirstParams(_params);
        _order.pendingSize = _params[1];
        _order.status = OrderStatus.PENDING;
        _order.positionType = POSITION_TRAILING_STOP;
        _order.stepType = _params[2];
        _order.stpPrice = _params[3];
        _order.stepAmount = _params[4];
        positionKeeper.unpackAndStorage(_key, abi.encode(_order), DataType.ORDER);
        positionKeeper.emitAddTrailingStopEvent(_key, _params);
    }

    function _cancelPendingOrder(
        bytes32 _key,
        OrderInfo memory _order
    ) internal {
        require(_order.status == OrderStatus.PENDING, "IVLOS/P"); //Invalid order status, must be pending
        require(_order.positionType != POSITION_MARKET, "NACMO"); //Not allowing cancel market order
        bool isTrailingStop = _order.positionType == POSITION_TRAILING_STOP;

        if (isTrailingStop) {
            require(_order.pendingCollateral > 0, "IVLOPDC");
        } else {
            require(_order.pendingCollateral > 0  && _order.collateralToken != address(0), "IVLOPDC/T"); //Invalid order pending collateral or token
        }
        
        _order.pendingCollateral = 0;
        _order.pendingSize = 0;
        _order.lmtPrice = 0;
        _order.stpPrice = 0;
        _order.collateralToken = address(0);

        if (isTrailingStop) {
            _order.status = OrderStatus.FILLED;
            _order.positionType = POSITION_MARKET;
        } else {
            _order.status = OrderStatus.CANCELED;
        }
        
        positionKeeper.unpackAndStorage(_key, abi.encode(_order), DataType.ORDER);
        positionKeeper.emitUpdateOrderEvent(_key, _order.positionType, _order.status);

        if (!isTrailingStop) {
            vault.takeAssetBack(
                positionKeeper.getPositionOwner(_key), 
                _key, 
                _getTxTypeFromPositionType(_order.positionType)
            );
        }
    }

    function _triggerPosition(
        bytes32 _key,
        address _collateralToken, 
        uint256 _indexPrice,
        uint256 _collateralPrice,
        Position memory _position, 
        OrderInfo memory _order
    ) internal {
        settingsManager.updateFunding(_position.indexToken, _collateralToken);
        uint8 statusFlag = vaultUtils.validateTrigger(_position.isLong, _indexPrice, _order);
        (bool hitTrigger, uint256 triggerAmountPercent) = triggerOrderManager.executeTriggerOrders(
            _position.owner,
            _position.indexToken,
            _position.isLong,
            _position.posId,
            _indexPrice
        );
        require(statusFlag == ORDER_FILLED || hitTrigger, "TGNRD");  //Trigger not ready

        //When TriggerOrder from TriggerOrderManager reached price condition
        if (hitTrigger) {
            _decreasePosition(
                _key,
                (_position.size * (triggerAmountPercent)) / BASIS_POINTS_DIVISOR,
                _collateralToken,
                _indexPrice,
                _collateralPrice,
                _position
            );
            _position = positionKeeper.getPosition(_key);
        }

        //When limit/stopLimit/stopMarket order reached price condition 
        if (statusFlag == ORDER_FILLED) {
            if (_order.positionType == POSITION_LIMIT || _order.positionType == POSITION_STOP_MARKET) {
                uint256 collateralDecimals = priceManager.getTokenDecimals(_order.collateralToken);
                _increasePosition(
                    _key,
                    _fromTokenToUSD(_order.pendingCollateral, _collateralPrice, collateralDecimals),
                    _fromTokenToUSD(_order.pendingSize, _collateralPrice, collateralDecimals),
                    _collateralToken,
                    _indexPrice,
                    _position
                );
                _order.pendingCollateral = 0;
                _order.pendingSize = 0;
                _order.status = OrderStatus.FILLED;
                _order.collateralToken = address(0);
            } else if (_order.positionType == POSITION_STOP_LIMIT) {
                _order.positionType = POSITION_LIMIT;
            } else if (_order.positionType == POSITION_TRAILING_STOP) {
                //Double check position size and collateral if hitTriggered
                if (_position.size > 0 && _position.collateral > 0) {
                    _decreasePosition(
                        _key,
                        _order.pendingSize, 
                        _collateralToken,
                        _indexPrice,
                        _collateralPrice, 
                        _position
                    );
                    _order.positionType = POSITION_MARKET;
                    _order.pendingCollateral = 0;
                    _order.pendingSize = 0;
                    _order.status = OrderStatus.FILLED;
                    _order.collateralToken = address(0);
                }
            }
        }

        positionKeeper.unpackAndStorage(_key, abi.encode(_order), DataType.ORDER);
        positionKeeper.emitUpdateOrderEvent(_key, _order.positionType, _order.status);
    }

    function _confirmDelayTransaction(
        bytes32 _key,
        address _collateralToken,
        uint256 _pendingCollateral,
        uint256 _pendingSize,
        uint256 _indexPrice,
        uint256 _collateralPrice,
        Position memory _position
    ) internal {
        vaultUtils.validateConfirmDelay(_key, true);
        //require(vault.getBondAmount(_key, ADD_POSITION) >= 0, "ISFBA"); //Insufficient bond amount
        uint256 pendingCollateralInUSD;
        uint256 pendingSizeInUSD;
      
        //Scope to avoid stack too deep error
        {
            uint256 collateralDecimals = priceManager.getTokenDecimals(_collateralToken);
            pendingCollateralInUSD = _fromTokenToUSD(_pendingCollateral, _collateralPrice, collateralDecimals);
            pendingSizeInUSD = _fromTokenToUSD(_pendingSize, _collateralPrice, collateralDecimals);
            require(pendingCollateralInUSD > 0 && pendingSizeInUSD > 0, "IVLPC"); //Invalid pending collateral
        }

        _increasePosition(
            _key,
            pendingCollateralInUSD,
            pendingSizeInUSD,
            _collateralToken,
            _indexPrice,
            _position
        );
        positionKeeper.emitConfirmDelayTransactionEvent(
            _key,
            true,
            _pendingCollateral,
            _pendingSize,
            _position.previousFee
        );
    }

    function _liquidatePosition(
        bytes32 _key,
        address _collateralToken,
        uint256 _indexPrice,
        uint256 _collateralPrice,
        Position memory _position
    ) internal {
        settingsManager.updateFunding(_position.indexToken, _collateralToken);
        (uint256 liquidationState, uint256 fee) = vaultUtils.validateLiquidation(
            false, //raise = false
            true, //isApplyTradingFee = true
            true, //isApplyBorrowFee = true
            true, //isApplyFundingFee = true
            _indexPrice,
            _position
        );
        require(liquidationState != LIQUIDATE_NONE_EXCEED, "NLS"); //Not liquidated state
        positionKeeper.updateGlobalShortData(_position.size, _indexPrice, false, abi.encode(_position));

        if (liquidationState == LIQUIDATE_THRESHOLD_EXCEED) {
            // Max leverage exceeded but there is collateral remaining after deducting losses so decreasePosition instead
            _decreasePosition(
                _key,
                _position.size, 
                _collateralToken, 
                _indexPrice, 
                _collateralPrice, 
                _position
            );
            positionKeeper.unpackAndStorage(_key, abi.encode(_position), DataType.POSITION);
            return;
        }

        vault.decreaseReservedAmount(_collateralToken, _position.reserveAmount);

        if (_position.isLong) {
            vault.decreaseGuaranteedAmount(_collateralToken, _position.size - _position.collateral);
        } 

        if (!_position.isLong && fee < _position.collateral) {
            uint256 remainingCollateral = _position.collateral - fee;
            vault.increasePoolAmount(_collateralToken, remainingCollateral);
        }

        vault.decreasePoolAmount(_collateralToken, fee);
        vault.transferBounty(settingsManager.feeManager(), fee);
        settingsManager.decreaseOpenInterest(_position.indexToken, _position.owner, _position.isLong, _position.size);
        positionKeeper.emitLiquidatePositionEvent(_key, _indexPrice, fee);
    }

    function _updateTrailingStop(
        bytes32 _key,
        bool _isLong,
        uint256 _indexPrice,
        OrderInfo memory _order
    ) internal {
        vaultUtils.validateTrailingStopPrice(_isLong, _key, true, _indexPrice);
        
        if (_isLong) {
            _order.stpPrice = _order.stepType == 0
                ? _indexPrice - _order.stepAmount
                : (_indexPrice * (BASIS_POINTS_DIVISOR - _order.stepAmount)) / BASIS_POINTS_DIVISOR;
        } else {
            _order.stpPrice = _order.stepType == 0
                ? _indexPrice + _order.stepAmount
                : (_indexPrice * (BASIS_POINTS_DIVISOR + _order.stepAmount)) / BASIS_POINTS_DIVISOR;
        }

        positionKeeper.unpackAndStorage(_key, abi.encode(_order), DataType.ORDER);
        positionKeeper.emitUpdateTrailingStopEvent(_key, _order.stpPrice);
    }

    function _increasePosition(
        bytes32 _key,
        uint256 _amountIn,
        uint256 _sizeDelta,
        address _collateralToken,
        uint256 _indexPrice,
        Position memory _position
    ) internal {
        settingsManager.updateFunding(_position.indexToken, _collateralToken);
        positionKeeper.updateGlobalShortData(_sizeDelta, _indexPrice, true, abi.encode(_position));
        uint256 fee;
        (fee, _position) = vaultUtils.increasePosition(
            _collateralToken,
            _amountIn,
            _sizeDelta,
            _indexPrice,
            _position
        );
        settingsManager.increaseOpenInterest(_position.indexToken, _position.owner, _position.isLong, _sizeDelta);
        positionKeeper.unpackAndStorage(_key, abi.encode(_position), DataType.POSITION);
        positionKeeper.emitIncreasePositionEvent(
            _key,
            _indexPrice,
            _amountIn, 
            _sizeDelta,
            fee
        );
    }

    function _decreasePosition(
        bytes32 _key,
        uint256 _sizeDelta,
        address _collateralToken,
        uint256 _indexPrice,
        uint256 _collateralPrice,
        Position memory _position
    ) internal {
        settingsManager.updateFunding(_position.indexToken, _collateralToken);
        settingsManager.decreaseOpenInterest(
            _position.indexToken,
            _position.owner,
            _position.isLong,
            _sizeDelta
        );

        positionKeeper.updateGlobalShortData(_sizeDelta, _indexPrice, false, abi.encode(_position));
        //usdOut, fee, collateralDelta
        bytes memory data = vaultUtils.decreasePosition(
            _sizeDelta,
            _collateralToken,
            _indexPrice,
            _position
        );

        bool isParitalClose;
        uint256 usdOut;
        uint256 fee;
        uint256 collateralDelta;
        int256 fundingFee;

        (isParitalClose, usdOut, fee, collateralDelta, fundingFee, _position) = abi.decode(data, (
            (bool), 
            (uint256), 
            (uint256), 
            (uint256),
            (int256), 
            (Position))
        );
        positionKeeper.unpackAndStorage(_key, abi.encode(_position), DataType.POSITION);
        positionKeeper.emitDecreasePositionEvent(
            _key,
            _indexPrice, 
            collateralDelta,
            _sizeDelta,
            fee,
            fundingFee,
            isParitalClose
        );

        if (fee <= usdOut) {
            //Transfer asset out if fee < usdOut
            vault.takeAssetOut(
                _key,
                _position.owner, 
                fee, //fee
                usdOut, //usdOut
                _collateralToken, 
                _collateralPrice
            );
        } else if (fee > 0) {
            //Distribute fee
            vault.distributeFee(_key, _position.owner, fee);
        }
    }

    function _fromTokenToUSD(uint256 _tokenAmount, uint256 _price, uint256 _decimals) internal pure returns (uint256) {
        return (_tokenAmount * _price) / (10 ** _decimals);
    }

    function _getOrderType(uint256 _positionType) internal pure returns (OrderType) {
        if (_positionType == POSITION_MARKET) {
            return OrderType.MARKET;
        } else if (_positionType == POSITION_LIMIT) {
            return OrderType.LIMIT;
        } else if (_positionType == POSITION_STOP_MARKET) {
            return OrderType.STOP;
        } else if (_positionType == POSITION_STOP_LIMIT) {
            return OrderType.STOP_LIMIT;
        } else {
            revert("Invalid orderType");
        }
    }

    function _getFirstPath(address[] memory _path) internal pure returns (address) {
        return _path[0];
    }

    function _getLastPath(address[] memory _path) internal pure returns (address) {
        return _path[_path.length - 1];
    }

    function _getFirstParams(uint256[] memory _params) internal pure returns (uint256) {
        return _params[0];
    }

    function _getLastParams(uint256[] memory _params) internal pure returns (uint256) {
        return _params[_params.length - 1];
    }

    function _validateExecutor(address _account) internal view {
        require(_isExecutor(_account), "FBD"); //Forbidden, not executor 
    }

    function _validatePositionKeeper() internal view {
        require(AddressUpgradeable.isContract(address(positionKeeper)), "IVLCA"); //Invalid contractAddress
    }

    function _validateVaultUtils() internal view {
        require(AddressUpgradeable.isContract(address(vaultUtils)), "IVLCA"); //Invalid contractAddress
    }

    function _validateRouter() internal view {
        require(AddressUpgradeable.isContract(address(positionRouter)), "IVLCA"); //Invalid contractAddress
    }

    function _getRevertMsg(bytes memory _returnData) internal pure returns (string memory) {
        //If the _res length is less than 68, then the transaction failed silently (without a revert message)
        if (_returnData.length < 68) {
            return "Transaction reverted silently";
        }

        assembly {
            // Slice the sighash.
            _returnData := add(_returnData, 0x04)
        }

        return abi.decode(_returnData, (string)); // All that remains is the revert string
    }

    function _validateAndDecodePositionData(
        uint256 _indexPrice,
        address[] memory _path,
        bytes memory _data
    ) internal view returns (
        bool isFastExecute,
        bool isNewPosition,
        uint256[] memory params,
        Position memory position,
        OrderInfo memory order
    ) {
        (
            isFastExecute,
            isNewPosition,
            params,
            position,
            order
        ) = abi.decode(_data, ((bool), (bool), (uint256[]), (Position), (OrderInfo)));
        
        {
            vaultUtils.validatePositionData(
                true,
                position.isLong,
                isFastExecute,
                _getOrderType(order.positionType), 
                _indexPrice, 
                _path,
                params
            );
        }

        return (isFastExecute, isNewPosition, params, position, order);
    }
}
