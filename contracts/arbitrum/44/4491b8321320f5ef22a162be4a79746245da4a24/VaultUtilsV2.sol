// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./OwnableUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./AddressUpgradeable.sol";

import "./IPriceManager.sol";
import "./IPositionRouterV2.sol";
import "./ISettingsManagerV2.sol";
import "./IPositionKeeperV2.sol";
import "./IVaultV2.sol";
import "./IVaultUtilsV2.sol";

import {Constants} from "./Constants.sol";
import {BasePositionConstants} from "./BasePositionConstants.sol";
import {Position, OrderInfo, PrepareTransaction, OrderStatus} from "./Structs.sol";

contract VaultUtilsV2 is IVaultUtilsV2, Constants, UUPSUpgradeable, OwnableUpgradeable {
    IPriceManager public priceManager;
    ISettingsManagerV2 public settingsManager;
    IPositionRouterV2 public positionRouter;
    address public positionHandler;
    IPositionKeeperV2 public positionKeeper;
    IVaultV2 public vault;
    uint256[50] private __gap;

    event FinalInitialized(
        address priceManager,
        address settingsManager,
        address vault,
        address positionHandler, 
        address positionKeeper, 
        address positionRouter
    );

    function initialize(
        address _priceManager, 
        address _settingsManager
    ) public reinitializer(3) {
        __Ownable_init();
        require(AddressUpgradeable.isContract(_priceManager)
            && AddressUpgradeable.isContract(_settingsManager), "IVLCA"); //Invalid contract address
        priceManager = IPriceManager(_priceManager);
        settingsManager = ISettingsManagerV2(_settingsManager);
    }

    function finalInitialize(
        address _vault,
        address _positionRouter,
        address _positionHandler,
        address _positionKeeper
    ) public onlyOwner {
       require(AddressUpgradeable.isContract(_vault)
            && AddressUpgradeable.isContract(_positionRouter)
            && AddressUpgradeable.isContract(_positionHandler)
            && AddressUpgradeable.isContract(_positionKeeper), "IVLCA"); //Invalid contract address
        vault = IVaultV2(_vault);
        positionRouter = IPositionRouterV2(_positionRouter);
        positionHandler = _positionHandler;
        positionKeeper = IPositionKeeperV2(_positionKeeper);
        emit FinalInitialized(
            address(priceManager), 
            address(settingsManager),
            _vault,
            _positionHandler,
            _positionKeeper,
            _positionRouter
        );
    }

    function _authorizeUpgrade(address) internal override onlyOwner {
        
    }

    function validateConfirmDelay(
        bytes32 _key,
        bool _raise
    ) external view override returns (bool) {
        PrepareTransaction memory transaction = positionRouter.getTransaction(_key);
        bool validateFlag;
        
        // uint256 public constant ADD_POSITION = 7;
        if (transaction.txType == 7) {
            if (block.timestamp >= (transaction.startTime + settingsManager.delayDeltaTime())) {
                validateFlag = true;
            } else {
                validateFlag = false;
            }
        } else {
            validateFlag = false;
        }

        if (_raise) {
            require(validateFlag, "Order is still in delay pending");
        }

        return validateFlag;
    }

    function validateDecreasePosition(
        bool _raise, 
        uint256 _indexPrice,
        Position memory _position
    ) external view override returns (bool) {
        return _validateDecreasePosition(
            _raise, 
            _indexPrice,
            _position
        );
    }

     function _validateDecreasePosition(
        bool _raise, 
        uint256 _indexPrice,
        Position memory _position
    ) internal view returns (bool) {
        bool validateFlag;
        (bool hasProfit, ) = priceManager.getDelta(
            _position.indexToken,
            _position.size,
            _position.averagePrice,
            _position.isLong,
            _indexPrice
        );

        if (hasProfit) {
            if (
                _position.lastIncreasedTime > 0 &&
                _position.lastIncreasedTime < block.timestamp - settingsManager.closeDeltaTime()
            ) {
                validateFlag = true;
            } else {
                uint256 price = _indexPrice > 0 ? _indexPrice : priceManager.getLastPrice(_position.indexToken);

                if (
                    (_position.isLong &&
                        price * BASIS_POINTS_DIVISOR >=
                        (BASIS_POINTS_DIVISOR + settingsManager.priceMovementPercent()) * _position.lastPrice) ||
                    (!_position.isLong &&
                        price * BASIS_POINTS_DIVISOR <=
                        (BASIS_POINTS_DIVISOR - settingsManager.priceMovementPercent()) * _position.lastPrice)
                ) {
                    validateFlag = true;
                }
            }
        } else {
            validateFlag = true;
        }

        if (_raise) {
            require(validateFlag, "Not allowed");
        }

        return validateFlag;
    }

    function validateLiquidation(
        bytes32 _key,
        bool _raise,
        bool _isApplyTradingFee,
        bool _isApplyBorrowFee,
        bool _isApplyFundingFee,
        uint256 _indexPrice
    ) public view returns (uint256, uint256) {
        Position memory position = positionKeeper.getPosition(_key);
        return validateLiquidation(
            _raise,
            _isApplyTradingFee,
            _isApplyBorrowFee, 
            _isApplyFundingFee,
            _indexPrice,
            position
        );
    }

    function validateLiquidation(
        bool _raise,
        bool _isApplyTradingFee,
        bool _isApplyBorrowFee,
        bool _isApplyFundingFee,
        uint256 _indexPrice,
        Position memory _position
    ) public view returns (uint256, uint256) {
        if (_position.averagePrice == 0) {
            return (LIQUIDATE_NONE_EXCEED, 0);
        }

        bool hasProfit;
        uint256 delta;
        uint256 fee;

        //Scope to avoid stack too deep error
        {
            (hasProfit, delta, fee, ) = _calculatePnl(
                _position.size,
                _position.size - _position.collateral,
                _indexPrice,
                _isApplyTradingFee,
                _isApplyBorrowFee,
                _isApplyFundingFee,
                true,
                _position
            );
        }

        return _checkPositionLiquidated(
            hasProfit,
            _raise,
            delta,
            fee,
            _position
        );
    }

    function validatePositionData(
        bool _raise,
        bool _isLong,
        bool _isLatestPrice,
        OrderType _orderType,
        uint256 _latestTokenPrice,
        address[] memory _path,
        uint256[] memory _params
    ) external view override returns (bool) {
        if (_raise) {
            require(_params.length == 8, "Invalid params length, must be 8");
        }

        //Validate minimum collateral amount > liquidationFee
        uint256 collateralInUSD = priceManager.fromTokenToUSD(_path[_path.length - 1], _params[4]);
        _checkMinimumOpenCollateral(collateralInUSD);

        bool orderTypeFlag;

        if (_params[5] == 0) {
            //Return true if size is zero
            return true;
        }

        if (!_isLatestPrice) {
            (_latestTokenPrice, , _isLatestPrice) = priceManager.getLatestSynchronizedPrice(_path[0]);
        }

        /*
        param[0] is mark price (for market type only, other type use 0)
        param[1] is slippage (for market type only, other type use 0)
        param[2] is limit price (for limit/stop/stop_limit type only, market use 0)
        param[3] is stop price (for limit/stop/stop_limit type only, market use 0)
        */

        if (_orderType == OrderType.LIMIT && _params[2] > 0) {
            //Limit type must have limit price > 0
            orderTypeFlag = true;
        } else if (_orderType == OrderType.STOP && _params[3] > 0) {
            //Stop type must have limit price > 0
            orderTypeFlag = true;
        } else if (_orderType == OrderType.STOP_LIMIT && _params[2] > 0 && _params[3] > 0) {
            //Stop-limit type must have both limit price and stop price > 0
            orderTypeFlag = true;
        } else if (_orderType == OrderType.MARKET) {
            //Market type need to check slippage
            checkSlippage(_isLong, _getFirstParams(_params), _getMarketSlippage(_params[1]), _latestTokenPrice);
            orderTypeFlag = true;
        }

        
        if (_raise) {
            require(orderTypeFlag, "Invalid positionData");
        }

        return (orderTypeFlag);
    }

    function _getMarketSlippage(uint256 _slippage) internal view returns (uint256) {
        uint256 defaultSlippage = settingsManager.positionDefaultSlippage();
        return _slippage >= BASIS_POINTS_DIVISOR || _slippage < defaultSlippage ? defaultSlippage : _slippage;
    }

    function validateTrailingStopInputData(
        bytes32 _key,
        bool _isLong,
        uint256[] memory _params,
        uint256 _indexPrice
    ) external view override returns (bool) {
        require(_params[1] > 0 && _params[1] <= positionKeeper.getPositionSize(_key), "Trailing size should be smaller than position size");
        
        if (_isLong) {
            require(_params[4] > 0 && _params[3] > 0 && _params[3] <= _indexPrice, "Invalid trailing data");
        } else {
            require(_params[4] > 0 && _params[3] > 0 && _params[3] >= _indexPrice, "Invalid trailing data");
        }

        if (_params[2] == TRAILING_STOP_TYPE_PERCENT) {
            require(_params[4] < BASIS_POINTS_DIVISOR, "Percent cant exceed 100%");
        } else {
            if (_isLong) {
                require(_params[4] < _indexPrice, "Step amount cant exceed price");
            }
        }

        return true;
    }

    function validateTrailingStopPrice(
        bool _isLong,
        bytes32 _key,
        bool _raise,
        uint256 _indexPrice
    ) external view override returns (bool) {
        OrderInfo memory order = positionKeeper.getOrder(_key);
        uint256 stopPrice;

        if (_isLong) {
            if (order.stepType == TRAILING_STOP_TYPE_AMOUNT) {
                stopPrice = order.stpPrice + order.stepAmount;
            } else {
                stopPrice = (order.stpPrice * BASIS_POINTS_DIVISOR) / (BASIS_POINTS_DIVISOR - order.stepAmount);
            }
        } else {
            if (order.stepType == TRAILING_STOP_TYPE_AMOUNT) {
                stopPrice = order.stpPrice - order.stepAmount;
            } else {
                stopPrice = (order.stpPrice * BASIS_POINTS_DIVISOR) / (BASIS_POINTS_DIVISOR + order.stepAmount);
            }
        }

        bool flag;

        if (
            _isLong &&
            order.status == OrderStatus.PENDING &&
            order.positionType == POSITION_TRAILING_STOP &&
            stopPrice <= _indexPrice
        ) {
            flag = true;
        } else if (
            !_isLong &&
            order.status == OrderStatus.PENDING &&
            order.positionType == POSITION_TRAILING_STOP &&
            stopPrice >= _indexPrice
        ) {
            flag = true;
        }

        if (_raise) {
            require(flag, "Incorrect price");
        }

        return flag;
    }

    function validateTrigger(
        bytes32 _key,
        uint256 _indexPrice
    ) external view override returns (uint8) {
        return _validateTrigger(
            positionKeeper.getPositionType(_key),
            _indexPrice,
            positionKeeper.getOrder(_key)
        );
    }

    function validateTrigger(
        bool _isLong,
        uint256 _indexPrice,
        OrderInfo memory _order
    ) external pure override returns (uint8) {
        return _validateTrigger(
            _isLong,
            _indexPrice,
            _order
        );
    }

    function _validateTrigger(
        bool _isLong,
        uint256 _indexPrice,
        OrderInfo memory _order
    ) internal pure returns (uint8) {
        uint8 statusFlag;

        if (_order.status == OrderStatus.PENDING) {
            if (_order.positionType == POSITION_LIMIT) {
                if (_isLong && _order.lmtPrice >= _indexPrice) {
                    statusFlag = ORDER_FILLED;
                } else if (!_isLong && _order.lmtPrice <= _indexPrice) {
                    statusFlag = ORDER_FILLED;
                } else {
                    statusFlag = ORDER_NOT_FILLED;
                }
            } else if (_order.positionType == POSITION_STOP_MARKET) {
                if (_isLong && _order.stpPrice <= _indexPrice) {
                    statusFlag = ORDER_FILLED;
                } else if (!_isLong && _order.stpPrice >= _indexPrice) {
                    statusFlag = ORDER_FILLED;
                } else {
                    statusFlag = ORDER_NOT_FILLED;
                }
            } else if (_order.positionType == POSITION_STOP_LIMIT) {
                if (_isLong && _order.stpPrice <= _indexPrice) {
                    statusFlag = ORDER_FILLED;
                } else if (!_isLong && _order.stpPrice >= _indexPrice) {
                    statusFlag = ORDER_FILLED;
                } else {
                    statusFlag = ORDER_NOT_FILLED;
                }
            } else if (_order.positionType == POSITION_TRAILING_STOP) {
                if (_isLong && _order.stpPrice >= _indexPrice) {
                    statusFlag = ORDER_FILLED;
                } else if (!_isLong && _order.stpPrice <= _indexPrice) {
                    statusFlag = ORDER_FILLED;
                } else {
                    statusFlag = ORDER_NOT_FILLED;
                }
            }
        } else {
            statusFlag = ORDER_NOT_FILLED;
        }
        
        return statusFlag;
    }

    function validatePositionSizeAndCollateral(uint256 _size, uint256 _collateral) external pure override {
        _validatePositionSizeAndCollateral(_size, _collateral);
    }

    function _validatePositionSizeAndCollateral(uint256 _size, uint256 _collateral) internal pure {
        require(_size >= _collateral, "Position size should be greater than collateral");
    }

    function _checkPositionLiquidated(
        bool _hasProfit,
        bool _raise,
        uint256 _pnl,
        uint256 _fee,
        Position memory _position
    ) internal view returns (uint256, uint256) {
        uint256 liquidationFeeInUSD;
        uint256 liquidateThreshold;
        bool isPositionExceedThreshold;

        {
            liquidationFeeInUSD = settingsManager.liquidationFeeUsd();
            (isPositionExceedThreshold, liquidateThreshold) = _isPositionExceedThreshold(
                _hasProfit,
                _position.indexToken,
                _position.collateral,
                _pnl + _fee
            );
        }

        if (isPositionExceedThreshold) {
            if (_raise) {
                revert("MaxThreshold exceeded");
            }

            return (LIQUIDATE_FEE_EXCEED, _getLiquidatedFee(_position.collateral, _fee, liquidationFeeInUSD));
        }

        uint256 remainingCollateral = !_hasProfit ? _position.collateral - _pnl : _position.collateral;

        if (remainingCollateral * priceManager.maxLeverage(_position.indexToken) < _position.size * MIN_LEVERAGE) {
            if (_raise) {
                revert("MaxLeverage exceeded");
            }

            return (LIQUIDATE_THRESHOLD_EXCEED, _fee);
        }

        //In testing
        // if (
        //     (remainingCollateral - liquidationFeeInUSD) <
        //     (_position.size * (BASIS_POINTS_DIVISOR - liquidateThreshold) / BASIS_POINTS_DIVISOR)
        // ) {
        //     if (_raise) {
        //         revert("MaxThreshold exceeded");
        //     }
            
        //     return (LIQUIDATE_THRESHOLD_EXCEED, _fee);
        // }

        return (LIQUIDATE_NONE_EXCEED, _fee);
    }

    function validatePositionSize(bytes32 _key, uint256 _txType, address _account) external view returns (bool) {
        if (_txType == ADD_POSITION || 
            _txType == ADD_COLLATERAL ||
            _txType == REMOVE_COLLATERAL ||
            _txType == ADD_TRAILING_STOP ||
            _txType == UPDATE_TRAILING_STOP || 
            _txType == CLOSE_POSITION) {
            Position memory position = positionKeeper.getPosition(_key);
            require(position.owner == _account, "Invalid positionOwner");
            require(position.size > 0, "Position not initialized");
        }

        return true;
    }

    function validateAmountIn(
        address _collateralToken,
        uint256 _amountIn,
        uint256 _collateralPrice
    ) external view returns (uint256) {
        return _validateAmountIn(
            _collateralToken,
            _amountIn,
            _collateralPrice
        );
    }

    function _validateAmountIn(
        address _collateralToken,
        uint256 _amountIn,
        uint256 _collateralPrice
    ) internal view returns (uint256){
        uint256 amountInUSD = priceManager.fromTokenToUSD(_collateralToken, _amountIn, _collateralPrice);
        require(amountInUSD > 0, "ZERO amountIn");
        return amountInUSD;
    }

    function validateAddOrRemoveCollateral(
        bytes32 _key,
        uint256 _amountIn,
        bool _isPlus,
        address _collateralToken,
        uint256 _indexPrice,
        uint256 _collateralPrice
    ) external view returns (uint256, Position memory) {
        return validateAddOrRemoveCollateral(
            _amountIn,
            _isPlus,
            _collateralToken,
            _indexPrice,
            _collateralPrice,
            positionKeeper.getPosition(_key)
        );
    }

    function validateAddOrRemoveCollateral(
        uint256 _amountIn,
        bool _isPlus,
        address _collateralToken,
        uint256 _indexPrice,
        uint256 _collateralPrice,
        Position memory _position
    ) public view returns (uint256, Position memory) {
        //If removeCollateral and collateralToken is stable, amountInUSD = amountIn
        uint256 amountInUSD = !_isPlus && settingsManager.isStable(_collateralToken) 
            ? _amountIn : _validateAmountIn(_collateralToken, _amountIn, _collateralPrice);

        if (!_isPlus) {
            require(_position.collateral >= amountInUSD && _position.reserveAmount >= amountInUSD, "Insufficient positionCollateral");
        }

        uint256 borrowFee = settingsManager.getBorrowFee(
            _position.indexToken, 
            _position.size - _position.collateral, 
            _position.lastIncreasedTime
        );
        _validatePositionSizeAndCollateral(_position.size, _isPlus ? _position.collateral + amountInUSD : _position.collateral - amountInUSD);

        if (_isPlus) {
            _position.collateral += amountInUSD;
            _position.reserveAmount += amountInUSD;
        } else {
            _position.collateral -= amountInUSD;
            _checkMinimumOpenCollateral(_position.collateral);
            _position.reserveAmount -= amountInUSD;
        }

        //Calculate newFee and set previous fee to ZERO to ignore previous fee on validateLiquidation
        uint256 newFee = _position.previousFee + borrowFee;
        _position.previousFee = newFee;

        if (newFee > 0) {
            require(_position.collateral >= newFee, "Fee exceeded positionCollateral");
        }

        validateLiquidation(
            true, //raise = true
            true, //isApplyTradingFee = true
            !_isPlus, //isApplyBorrowFee = false for addCollateral, otherwise = true
            !_isPlus, //isApplyFundingFee = false for addCollateral, otherwise = true
            _indexPrice,
            _position
        );
        _position.lastIncreasedTime = block.timestamp;
        return (amountInUSD, _position);
    }

    function beforeDecreasePositionV2(
        bytes32 _key,
        uint256 _sizeDelta,
        uint256 _indexPrice
    ) external view returns (bool, int256, uint256[4] memory, Position memory) {
        Position memory position = positionKeeper.getPosition(_key);
        bool hasProfit;
        bytes memory encodedData;
        int256 fundingFee;

        (hasProfit, fundingFee, encodedData) = _beforeDecreasePosition(
            _sizeDelta,
            _indexPrice,
            position
        );

        uint256[4] memory posData;
        (posData, position) = abi.decode(encodedData, ((uint256[4]), (Position)));
        return (hasProfit, fundingFee, posData, position);
    }

    function beforeDecreasePosition(
        uint256 _sizeDelta,
        uint256 _indexPrice,
        Position memory _position
    ) external view returns (bool, int256, bytes memory) {
        return _beforeDecreasePosition(
            _sizeDelta,
            _indexPrice,
            _position
        );
    }

    function _beforeDecreasePosition(
        uint256 _sizeDelta,
        uint256 _indexPrice,
        Position memory _position
    ) internal view returns (bool, int256, bytes memory) {
        _isValidPosition(_position);
        uint256 decreaseReserveAmount = (_position.reserveAmount * _sizeDelta) / _position.size;
        require(decreaseReserveAmount <= _position.reserveAmount, "Insufficient positionReserve");
        _position.reserveAmount -= decreaseReserveAmount;
        uint256[4] memory posData;
        bool hasProfit;
        int256 fundingFee;

        {
            //posData: [usdOut, tradingFee, collateralDelta, adjustedDelta]
            (hasProfit, fundingFee, posData) = _reduceCollateral(
                _sizeDelta, 
                _indexPrice, 
                _position
            );
        }

        if (_position.size != _sizeDelta) {
            _position.entryFunding = settingsManager.fundingIndex(_position.indexToken);
            require(_sizeDelta <= _position.size, "PositionSize exceeded");
            _position.size -= _sizeDelta;
            _validatePositionSizeAndCollateral(_position.size, _position.collateral);
            validateLiquidation(
                true, //raise = true
                false, //isApplyTradingFee = false;
                false, //isApplyBorrowFee = flase
                false, //isApplyFundingFee = false
                _indexPrice, 
                _position
            );
        } else {
            _position.size = 0;
        }

        return (hasProfit, fundingFee, abi.encode(posData, _position));
    }

    function _reduceCollateral(
        uint256 _sizeDelta,
        uint256 _indexPrice, 
        Position memory _position
    ) internal view returns (bool, int256, uint256[4] memory) {
        bool hasProfit;
        uint256 adjustedDelta;
        uint256 tradingFee;
        int256 fundingFee;

        //Scope to avoid stack too deep error
        {
            uint256 delta;
            (hasProfit, delta, tradingFee, fundingFee) = _calculatePnlNoneLiquidate(
                _sizeDelta,
                _position.size - _position.collateral,
                _indexPrice,
                true, //isApplyTradingFee = true
                true, //isApplyBorrowFee = true
                true, //isApplyFundingFee = true
                _position
            );
            adjustedDelta = (_sizeDelta * delta) / _position.size;
        }

        uint256 collateralDelta;

        {
            collateralDelta = (_position.collateral * _sizeDelta) / _position.size;
        }

        uint256 usdOut;

        if (adjustedDelta > 0) {
            if (hasProfit) {
                usdOut = adjustedDelta;
                _position.realisedPnl += int256(adjustedDelta);
            } else {
                _position.collateral = _position.collateral < adjustedDelta ? 0 : _position.collateral - adjustedDelta;
                _position.realisedPnl -= int256(adjustedDelta);
            }
        }

        // If the position will be closed, then transfer the remaining collateral out
        if (_position.size == _sizeDelta) {
            usdOut += _position.collateral;
            _position.collateral = 0;
        } else {
            // Reduce the position's collateral by collateralDelta, transfer collateralDelta out
            usdOut += collateralDelta;
            _position.collateral -= collateralDelta;
        }
        
        // If the usdOut is more or equal than the fee then deduct the fee from the usdOut directly
        // else deduct the fee from the position's collateral
        if (usdOut < tradingFee) {
            require(tradingFee <= _position.collateral, "Insufficient position collateral to deduct fee");
            _position.collateral -= tradingFee;
        }

        _validateDecreasePosition(true, _indexPrice, _position);
        return (hasProfit, fundingFee, [usdOut, tradingFee, collateralDelta, adjustedDelta]);
    }

    function calculatePnl(
        uint256 _sizeDelta,
        uint256 _loanDelta,
        uint256 _indexPrice,
        bool _isApplyTradingFee,
        bool _isApplyBorrowFee,
        bool _isApplyFundingFee,
        bool _isLiquidated,
        Position memory _position
    ) external view returns (bool, uint256, uint256, int256) {
        return _calculatePnl(
            _sizeDelta,
            _loanDelta,
            _indexPrice,
            _isApplyTradingFee,
            _isApplyBorrowFee,
            _isApplyFundingFee,
            _isLiquidated,
            _position
        );
    }

    function calculatePnlV2(
        bytes32 _key,
        uint256 _sizeDelta,
        uint256 _loanDelta,
        uint256 _indexPrice,
        bool _isApplyTradingFee,
        bool _isApplyBorrowFee,
        bool _isApplyFundingFee,
        bool _isLiquidated
    ) external view returns (bool, uint256, uint256, int256) {
        Position memory position;

        //Scope to avoid stack too deep error
        {
            position = positionKeeper.getPosition(_key);
        }

        return _calculatePnl(
            _sizeDelta,
            _loanDelta,
            _indexPrice,
            _isApplyTradingFee,
            _isApplyBorrowFee,
            _isApplyFundingFee,
            _isLiquidated,
            position
        );
    }

    function _calculatePnl(
        uint256 _sizeDelta,
        uint256 _loanDelta,
        uint256 _indexPrice,
        bool _isApplyTradingFee,
        bool _isApplyBorrowFee,
        bool _isApplyFundingFee,
        bool _isLiquidated,
        Position memory _position
    ) internal view returns (bool, uint256, uint256, int256) {
        _isValidPosition(_position);
        int256 pnl;

        //Scope to avoid stack too deep error
        {
            int256 multiplier = _position.isLong ? (_indexPrice >= _position.averagePrice ? int256(1) : int256(-1)) 
                : (_indexPrice >= _position.averagePrice ? int256(-1) : int256(1));

            pnl = multiplier * int256((_position.size * 
                (
                    //priceDiff
                    _indexPrice >= _position.averagePrice 
                        ? _indexPrice - _position.averagePrice 
                        : _position.averagePrice - _indexPrice
                ) 
            ) / _position.averagePrice);
        }

        //TradingFee include marginFee + borrowFee + previousFee (openFee) 
        uint256 tradingFee;
        int fundingFee;
        
        {
            (tradingFee, fundingFee) = _getFees(
                _sizeDelta, 
                _loanDelta,
                _isApplyTradingFee,
                _isApplyBorrowFee, 
                _isApplyFundingFee, 
                _position
            );
        }

        //Not apply bonus fundingFee if position is liquidated
        if (_isLiquidated && fundingFee < 0) {
            fundingFee = 0;
        }

        if (fundingFee != 0) {
            pnl -= fundingFee;
        }

        return pnl > 0 ? (true, uint256(pnl), tradingFee, fundingFee) 
            : (false, uint256(-1 * pnl), tradingFee, fundingFee);
    }

    function _calculatePnlNoneLiquidate(
        uint256 _sizeDelta,
        uint256 _loanDelta,
        uint256 _indexPrice,
        bool _isApplyTradingFee,
        bool _isApplyBorrowFee,
        bool _isApplyFundingFee,
        Position memory _position
    ) internal view returns (bool, uint256, uint256, int256) {
        return _calculatePnl(
            _sizeDelta,
            _loanDelta,
            _indexPrice,
            _isApplyTradingFee,
            _isApplyBorrowFee,
            _isApplyFundingFee,
            false,
            _position
        );
    }

    function _getFees(
        uint256 _sizeDelta,
        uint256 _loanDelta,
        bool _isApplyTradingFee,
        bool _isApplyBorrowFee,
        bool _isApplyFundingFee,
        Position memory _position
    ) internal view returns (uint256, int256){
        return settingsManager.getFees(
            _sizeDelta,
            _loanDelta,
            _isApplyTradingFee,
            _isApplyBorrowFee, 
            _isApplyFundingFee,
            _position
        );
    }

    function _getFirstParams(uint256[] memory _params) internal pure returns (uint256) {
        return _params[0];
    }

    function reIncreasePosition(
        uint256 _sizeDelta,
        uint256 _indexPrice, 
        Position memory _position
    ) external view returns (uint256, int256) {
        return _reIncreasePosition(
            _sizeDelta,
            _indexPrice, 
            _position
        );
    }

    function _reIncreasePosition(
        uint256 _sizeDelta,
        uint256 _indexPrice, 
        Position memory _position
    ) internal view returns (uint256, int256) {
        uint256 averagePrice = _sizeDelta == 0 ? _position.averagePrice 
            : priceManager.getNextAveragePrice(
                _position.indexToken,
                _position.size,
                _position.averagePrice,
                _position.isLong,
                _sizeDelta,
                _indexPrice
        );
        int256 entryFunding =
            (int256(_position.size) *
                _position.entryFunding +
                int256(_sizeDelta) *
                settingsManager.fundingIndex(_position.indexToken)) /
            int256(_position.size + _sizeDelta);

        return (averagePrice, entryFunding);
    }

    function increasePosition(
        address _collateralToken,
        uint256 _amountIn,
        uint256 _sizeDelta,
        uint256 _indexPrice,
        Position memory _position
    ) external returns (uint256, Position memory) {
        require(msg.sender == positionHandler, "FBD");
        require(_sizeDelta > 0, "IVLPSD"); //Invalid position sizeDelta
        uint256 fee;
        bool isNewPosition = _position.size == 0;

        if (isNewPosition) {
            _position.averagePrice = _indexPrice;
            _position.entryFunding = settingsManager.fundingIndex(_position.indexToken);
            (fee, ) = settingsManager.getFees(
                _sizeDelta,
                0,
                true,
                false,
                false,
                _position
            );
        } else {
            (uint256 newAvgPrice, int256 newEntryFunding) = _reIncreasePosition(
                _sizeDelta, 
                _indexPrice, 
                _position
            );
            require(newAvgPrice > 0, "IVLAP/Z"); //Invalid avgPrice/zero
            _position.averagePrice = newAvgPrice;
            _position.entryFunding = newEntryFunding;
            (fee, ) = settingsManager.getFees(
                _sizeDelta,
                _position.size - _position.collateral, //previousLoanDelta
                true,
                true,
                false,
                _position
            );
            //Reset previousFee to zero due to settingsManager.getFees() alredy adding previousFee to tradingFee
            _position.previousFee = 0;
        }

        //Storage fee and charge later
        _position.previousFee += fee;
        _position.collateral += _amountIn;
        _position.reserveAmount += _amountIn;
        _position.size += _sizeDelta;
        _position.lastIncreasedTime = block.timestamp;
        _position.lastPrice = _indexPrice;
        
        settingsManager.validatePosition(
            _position.owner, 
            _position.indexToken, 
            _position.isLong, 
            _position.size, 
            _position.collateral
        );

        validateLiquidation(
            true, //raise = true
            isNewPosition ? false : true, //isApplyTradingFee = true for oldPosition and otherwise
            isNewPosition ? false : true, //isApplyBorrowFee = false for oldPosition and otherwise
            isNewPosition ? false : true, //isApplyFundingFee = false for oldPosition and otherwise
            _indexPrice, 
            _position
        );

        vault.increaseReservedAmount(_collateralToken, _sizeDelta);

        if (_position.isLong) {
            //Only increase pool amount for long position
            vault.increasePoolAmount(_collateralToken, _amountIn);
            vault.decreasePoolAmount(_collateralToken, uint256(fee));
            vault.increaseGuaranteedAmount(_collateralToken, _sizeDelta + uint256(fee));
            vault.decreaseGuaranteedAmount(_collateralToken, _amountIn);
        } 

        return (fee, _position);
    }

    function decreasePosition(
        uint256 _sizeDelta,
        address _collateralToken,
        uint256 _indexPrice,
        Position memory _position
    ) external returns (bytes memory) {
        require(msg.sender == positionHandler, "FBD");
        //Decrease reserveDelta
        vault.decreaseReservedAmount(_collateralToken, _position.reserveAmount * _sizeDelta / _position.size);

        bool hasProfit;
        bool isPartialClose;
        uint256 prevCollateral;
        uint256[4] memory posData; //[usdOut, fee, collateralDelta, adjustedDelta]
        int256 fundingFee;

        //Scope to avoid stack too deep error
        {
            prevCollateral = _position.collateral;
            bytes memory encodedData;
            (hasProfit, fundingFee, encodedData) = _beforeDecreasePosition(
                _sizeDelta, 
                _indexPrice, 
                _position
            );
            isPartialClose = _position.size != _sizeDelta;
            (posData, _position) = abi.decode(encodedData, ((uint256[4]), (Position)));
        }

        if (isPartialClose && _position.previousFee > 0) {
            //Reset previousFee (openFee) to zero, tradingFee already addeed previousFee in settingsManager.getFees()
            _position.previousFee = 0;
        }

        //adjustedDelta > 0
        if (posData[3] > 0) {
            if (hasProfit && !_position.isLong) {
            // Pay out realised profits from the pool amount for short positions
                vault.decreasePoolAmount(_collateralToken, posData[3]);
            } else if (!hasProfit && !_position.isLong) {
            // Transfer realised losses to the pool for short positions
            // realised losses for long positions are not transferred here as
            // increasePoolAmount was already called in increasePosition for longs
                vault.increasePoolAmount(_collateralToken, posData[3]);
            }
        }

        if (_position.isLong) {
            vault.increaseGuaranteedAmount(_collateralToken, 
                isPartialClose ? prevCollateral - _position.collateral : prevCollateral);
            vault.decreaseGuaranteedAmount(_collateralToken, _sizeDelta);

            if (posData[0] > 0) {
                //Decrease pool amount if usdOut > 0 and position is long
                vault.decreasePoolAmount(_collateralToken, posData[0]);
            }
        }

        return abi.encode(
            isPartialClose, 
            posData[0], //usdOut
            posData[1], //fee
            posData[2], //collateralDelta
            fundingFee, 
            _position
        );
    }

    function _isValidPosition(Position memory _position) internal pure {
        require(_position.owner != address(0), "Position notExist");
    }

    function getPositionKey(address _account, address _indexToken, bool _isLong, uint256 _posId) external pure returns (bytes32) {
        return _getPositionKey(_account, _indexToken, _isLong, _posId);
    }

    function _isPositionExceedThreshold(
        bool _hasProfit,
        address _indexToken,
        uint256 _collateral,
        uint256 _pnl
    ) internal view returns (bool, uint256) {
        if (_hasProfit) {
            return (false, BASIS_POINTS_DIVISOR);
        }

        uint256 liquidateThreshold = settingsManager.liquidateThreshold(_indexToken);

        //Default threshold = 100%
        if (liquidateThreshold == 0) {
            liquidateThreshold = BASIS_POINTS_DIVISOR;
        }

        return (!_hasProfit && _pnl >= (_collateral * liquidateThreshold / BASIS_POINTS_DIVISOR), liquidateThreshold);
    }

    function _getLiquidatedFee(
        uint256 _collateral,
        uint256 _fee,
        uint256 _liquidationFeeInUSD
    ) internal pure returns ( uint256) {
        if (_collateral < _fee) {
            return _collateral;
        }

        if (_collateral < _fee + _liquidationFeeInUSD) {
            return _fee;
        }

        if (_collateral >= _fee + _liquidationFeeInUSD) {
            return _fee + _liquidationFeeInUSD;
        }

        return _fee;
    }

    function _checkMinimumOpenCollateral(uint256 _collateral) internal view {
        require(_collateral > settingsManager.minimumOpenCollateral(), "MinimumOpenCollateral reached");
    }
}
