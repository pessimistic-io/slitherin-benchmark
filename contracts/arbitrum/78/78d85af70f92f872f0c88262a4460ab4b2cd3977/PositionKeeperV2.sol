// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./UUPSUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./PositionConstants.sol";
import "./IPriceManager.sol";
import "./IMintable.sol";

import "./IPositionKeeperV2.sol";

contract PositionKeeperV2 is IPositionKeeperV2, PositionConstants, UUPSUpgradeable,
        OwnableUpgradeable, ReentrancyGuardUpgradeable {
    IPriceManager public priceManager;
    address public positionHandler;

    uint256 public shortsTrackerAveragePriceWeight;

    mapping(address => uint256) public override lastPositionIndex;
    mapping(bytes32 => Position) public positions;
    mapping(bytes32 => OrderInfo) public orders;
    mapping(bytes32 => FinalPath) public finalPaths;

    mapping(bytes32 => uint256) public override leverages;
    mapping(address => mapping(bool => uint256)) public override globalAmounts; //Global long/short trading amount
    mapping (address => uint256) public globalShortAveragePrices;
    uint256[50] private __gap;

    struct FinalPath {
        address indexToken;
        address collateralToken;
    }

    event FinalInitialized(
        address priceManager, 
        address positionHandler
    );
    event NewOrder(
        bytes32 key,
        address indexed account,
        bool isLong,
        uint256 posId,
        uint256 positionType,
        OrderStatus orderStatus,
        address[] path,
        uint256[] triggerData
    );
    event AddOrRemoveCollateral(
        bytes32 indexed key,
        bool isPlus,
        uint256 nativeAmount,
        uint256 amountInUSD,
        uint256 reserveAmount,
        uint256 collateral,
        uint256 size
    );
    event AddPosition(bytes32 indexed key, bool confirmDelayStatus, uint256 collateral, uint256 size);
    event AddTrailingStop(bytes32 key, uint256[] data);
    event UpdateTrailingStop(bytes32 key, uint256 stpPrice);
    event UpdateOrder(bytes32 key, uint256 positionType, OrderStatus orderStatus);
    event ConfirmDelayTransactionExecuted(
        bytes32 indexed key,
        bool confirmDelayStatus,
        uint256 collateral,
        uint256 size,
        uint256 feeUsd
    );
    event PositionExecuted(
        bytes32 key,
        address indexed account,
        address indexToken,
        bool isLong,
        uint256 posId,
        uint256[] prices
    );
    event IncreasePosition(
        bytes32 key,
        address indexed account,
        address indexed indexToken,
        bool isLong,
        uint256 posId,
        int256 entryFunding,
        uint256[6] posData
    );
    event ClosePosition(
        bytes32 key, 
        int256 realisedPnl, 
        uint256 markPrice, 
        uint256[2] posData,
        uint256 tradingFee,
        int256 fundingFee
    );
    event DecreasePosition(
        bytes32 key,
        address indexed account,
        address indexed indexToken,
        bool isLong,
        uint256 posId,
        uint256[5] posData,
        int256 realisedPnl,
        int256 entryFunding,
        uint256 tradingFee,
        int256 fundingFee
    );
    event LiquidatePosition(bytes32 key, int256 realisedPnl, uint256 markPrice, uint256 feeUsd);
    event GlobalShortDataUpdated(address indexed token, uint256 globalShortSize, uint256 globalShortAveragePrice);
    
    modifier onlyPositionHandler() {
        require(msg.sender == positionHandler, "Forbidden");
        _;
    }

    function initialize(
        address _priceManager,
        address _positionHandler
    ) public initializer {
        __Ownable_init();
        _finalInitialize(
            _priceManager,
            _positionHandler
        );
    }

    function _finalInitialize(
        address _priceManager,
        address _positionHandler
    ) internal {
        require(AddressUpgradeable.isContract(_priceManager)
            && AddressUpgradeable.isContract(_positionHandler), "Invalid contract");
        priceManager = IPriceManager(_priceManager);
        positionHandler = _positionHandler;
        emit FinalInitialized(_priceManager, _positionHandler);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {
        
    }

    function openNewPosition(
        bytes32 _key,
        bool _isLong, 
        uint256 _posId,
        address[] memory _path,
        uint256[] memory _params,
        bytes memory _data
    ) external nonReentrant onlyPositionHandler {
        Position memory position;
        OrderInfo memory order;

        //Scope to avoid stack too deep error
        {
            //Min encode data length for position 13 struct and order 9 struct are 22 * 32 = 704

            if (_data.length < 704) {
                //For market position, already storaged position by unpackAndStorage from PositionHandler._increasePosition
                orders[_key] = abi.decode(_data, (OrderInfo));
            } else {
                //Storage position and order for delay position
                (positions[_key], orders[_key]) = abi.decode(_data, ((Position), (OrderInfo)));
            }

            position = positions[_key];
            order = orders[_key];
        }

        if (finalPaths[_key].collateralToken == address(0)) {
            finalPaths[_key].collateralToken = _path[_path.length - 1];
            finalPaths[_key].indexToken = _path[0];
        }

        emit NewOrder(
            _key, 
            position.owner, 
            _isLong, 
            _posId, 
            order.positionType, 
            order.status, 
            _path,
            _params
        );

        lastPositionIndex[position.owner] += 1;
    }

    function unpackAndStorage(bytes32 _key, bytes memory _data, DataType _dataType) external nonReentrant onlyPositionHandler {
        if (_dataType == DataType.POSITION) {
            positions[_key] = abi.decode(_data, (Position));
            uint256 leverage = positions[_key].size == 0 && positions[_key].collateral == 0 
                ? 0 : positions[_key].size * BASIS_POINTS_DIVISOR / positions[_key].collateral;
            leverages[_key] = leverage;
        } else if (_dataType == DataType.ORDER) {
            orders[_key] = abi.decode(_data, (OrderInfo));
        } else {
            revert("Invalid data type");
        }
    }

    function deletePosition(bytes32 _key) external override nonReentrant onlyPositionHandler {
        _deletePositions(_key, false);
    }

    function deleteOrder(bytes32 _key) external override nonReentrant onlyPositionHandler {
        delete orders[_key];
    }

    function deletePositions(bytes32 _key) external override nonReentrant onlyPositionHandler {
        _deletePositions(_key, true);
    } 

    function _deletePositions(bytes32 _key, bool _isDeleteOrder) internal {
        if (_isDeleteOrder) {
            delete orders[_key];
        }

        delete positions[_key];
    }

    //Emit event functions
    function emitAddPositionEvent(
        bytes32 key, 
        bool confirmDelayStatus, 
        uint256 collateral, 
        uint256 size
    ) external nonReentrant onlyPositionHandler {
        emit AddPosition(key, confirmDelayStatus, collateral, size);
    }

    function emitAddOrRemoveCollateralEvent(
        bytes32 _key,
        bool _isPlus,
        uint256 _amount,
        uint256 _amountInUSD,
        uint256 _reserveAmount,
        uint256 _collateral,
        uint256 _size
    ) external nonReentrant onlyPositionHandler {
        emit AddOrRemoveCollateral(
            _key,
            _isPlus,
            _amount,
            _amountInUSD,
            _reserveAmount,
            _collateral,
            _size
        );
    }

    function emitAddTrailingStopEvent(bytes32 _key, uint256[] memory _data) external nonReentrant onlyPositionHandler {
        emit AddTrailingStop(_key, _data);
    }

    function emitUpdateTrailingStopEvent(bytes32 _key, uint256 _stpPrice) external nonReentrant onlyPositionHandler {
        emit UpdateTrailingStop(_key, _stpPrice);
    }

    function emitUpdateOrderEvent(bytes32 _key, uint256 _positionType, OrderStatus _orderStatus) external nonReentrant onlyPositionHandler {
        emit UpdateOrder(_key, _positionType, _orderStatus);
    }

    function emitConfirmDelayTransactionEvent(
        bytes32 _key,
        bool _confirmDelayStatus,
        uint256 _collateral,
        uint256 _size,
        uint256 _feeUsd
    ) external nonReentrant onlyPositionHandler {
        emit ConfirmDelayTransactionExecuted(_key, _confirmDelayStatus, _collateral, _size, _feeUsd);
    }

    function emitPositionExecutedEvent(
        bytes32 _key,
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256[] memory _prices
    ) external nonReentrant onlyPositionHandler {
        emit PositionExecuted(
            _key,
            _account,
            _indexToken,
            _isLong,
            _posId,
            _prices
        );
    }

    function emitIncreasePositionEvent(
        bytes32 _key,
        uint256 _indexPrice,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        uint256 _fee
    ) external nonReentrant onlyPositionHandler {
        Position memory position = positions[_key];
        globalAmounts[position.indexToken][position.isLong] += _sizeDelta;

        emit IncreasePosition(
            _key,
            position.owner,
            position.indexToken,
            position.isLong,
            position.posId,
            position.entryFunding,
            [
                _collateralDelta,
                _sizeDelta,
                position.reserveAmount,
                position.averagePrice,
                _indexPrice,
                _fee
            ]
        );
    }

    function emitDecreasePositionEvent(
        bytes32 _key,
        uint256 _indexPrice,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        uint256 _tradingFee,
        int256 _fundingFee,
        bool _isPartialClose
    ) external override onlyPositionHandler {
        Position memory position = positions[_key];
        _decreaseGlobalAmount(_sizeDelta, position.indexToken, position.isLong);

        if (_isPartialClose) {
            emit DecreasePosition(
                _key,
                position.owner,
                position.indexToken,
                position.isLong,
                position.posId,
                [
                    _collateralDelta,
                    _sizeDelta,
                    position.reserveAmount,
                    position.averagePrice,
                    _indexPrice
                ],
                position.realisedPnl,
                position.entryFunding,
                _tradingFee,
                _fundingFee
            );
        } else {
            delete leverages[_key];
            emit ClosePosition(
                _key, 
                position.realisedPnl, 
                _indexPrice, 
                [
                    _collateralDelta, 
                    _sizeDelta
                ],
                _tradingFee,
                _fundingFee
            );
            delete positions[_key];
        }
    }

    function _decreaseGlobalAmount(uint256 _sizeDelta, address _indexToken, bool _isLong) internal {
        uint256 globalAmount = globalAmounts[_indexToken][_isLong];
        uint256 decreaseGlobalAmount = _sizeDelta > globalAmount ? globalAmount : _sizeDelta;
        globalAmounts[_indexToken][_isLong] -= decreaseGlobalAmount;
    }

    function emitLiquidatePositionEvent(
        bytes32 _key,
        uint256 _indexPrice,
        uint256 _fee
    ) external override onlyPositionHandler {
        Position memory position = positions[_key];
        _decreaseGlobalAmount(position.size, position.indexToken, position.isLong);
        emit LiquidatePosition(_key, position.realisedPnl, _indexPrice, _fee);
        delete positions[_key];
    }
    //End emit event functions

    //View functions
    function getPositions(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external view override returns (Position memory, OrderInfo memory) {
        bytes32 key = _getPositionKey(_account, _indexToken, _isLong, _posId);
        Position memory position = positions[key];
        OrderInfo memory order = orders[key];
        return (position, order);
    }

    function getPositions(bytes32 _key) external view override returns (Position memory, OrderInfo memory) {
        return (positions[_key], orders[_key]);
    }

    function getPosition(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external view override returns (Position memory) {
        return positions[_getPositionKey(_account, _indexToken, _isLong, _posId)];
    }

    function getPosition(bytes32 _key) external override view returns (Position memory) {
        return positions[_key];
    }

    function getOrder(bytes32 _key) external override view returns (OrderInfo memory) {
        return orders[_key];
    }

    function getPositionPreviousFee(bytes32 _key) external override view returns (uint256) {
        return positions[_key].previousFee;
    }

    function getPositionSize(bytes32 _key) external override view returns (uint256) {
        return positions[_key].size;
    } 

    function getPositionCollateralToken(bytes32 _key) external override view returns (address) {
        return finalPaths[_key].collateralToken;
    }

    function getPositionIndexToken(bytes32 _key) external override view returns (address) {
        return finalPaths[_key].indexToken;
    }

    function getPositionFinalPath(bytes32 _key) external override view returns (address[] memory) {
        address[] memory finalPath = new address[](2);
        finalPath[0] = finalPaths[_key].indexToken;
        finalPath[1] = finalPaths[_key].collateralToken;
        return finalPath;
    }

    function getPositionOwner(bytes32 _key) external override view returns (address) {
        return positions[_key].owner;
    }

    function getPositionType(bytes32 _key) external override view returns (bool) {
        return positions[_key].isLong;
    }

    function getBasePosition(bytes32 _key) external override view returns (address, address, bool, uint256) {
        return (positions[_key].owner, positions[_key].indexToken, positions[_key].isLong, positions[_key].posId);
    }

    function setShortsTrackerAveragePriceWeight(uint256 _shortsTrackerAveragePriceWeight) external onlyOwner {
        require(shortsTrackerAveragePriceWeight <= BASIS_POINTS_DIVISOR, "Invalid weight");
        shortsTrackerAveragePriceWeight = _shortsTrackerAveragePriceWeight;
    }

    function getGlobalShortDelta(address _token) public view returns (bool, uint256) {
        uint256 size = globalAmounts[_token][false];
        uint256 averagePrice = globalShortAveragePrices[_token];
        if (size == 0) { return (false, 0); }

        uint256 nextPrice = priceManager.getLastPrice(_token);
        uint256 priceDelta = averagePrice > nextPrice ? averagePrice - nextPrice : nextPrice - averagePrice;
        uint256 delta = (size * priceDelta) / averagePrice;
        bool hasProfit = averagePrice > nextPrice;

        return (hasProfit, delta);
    }

    function updateGlobalShortData(
        uint256 _sizeDelta,
        uint256 _indexPrice,
        bool _isIncrease,
        bytes memory _data
    ) external {
        require(msg.sender == address(positionHandler), "Forbidden");
        Position memory position = abi.decode(_data, (Position));

        if (position.isLong || _sizeDelta == 0) {
            return;
        }

        (uint256 globalShortSize, uint256 globalShortAveragePrice) = getNextGlobalShortData(
            _indexPrice,
            _sizeDelta,
            _isIncrease,
            position
        );

        globalShortAveragePrices[position.indexToken] = globalShortAveragePrice;
        emit GlobalShortDataUpdated(position.indexToken, globalShortSize, globalShortAveragePrice);
    }

    function getNextGlobalShortData(
        uint256 _indexPrice,
        uint256 _sizeDelta,
        bool _isIncrease,
        Position memory _position
    ) public view returns (uint256, uint256) {
        int256 realisedPnl = _getRealisedPnl(_sizeDelta, _isIncrease, _position);
        uint256 averagePrice = globalShortAveragePrices[_position.indexToken];
        uint256 priceDelta = averagePrice > _indexPrice ? averagePrice - _indexPrice : _indexPrice - averagePrice;

        uint256 nextSize;
        uint256 delta;

        {
            uint256 size = globalAmounts[_position.indexToken][false];
            nextSize = _isIncrease ? size + _sizeDelta : size - _sizeDelta;

            if (nextSize == 0) {
                return (0, 0);
            }

            if (averagePrice == 0) {
                return (nextSize, _indexPrice);
            }

            delta = (size * priceDelta) / averagePrice;
        }

        uint256 nextAveragePrice = getNextGlobalAveragePrice(
            averagePrice,
            _indexPrice,
            nextSize,
            delta,
            realisedPnl
        );

        return (nextSize, nextAveragePrice);
    }

    function getNextGlobalAveragePrice(
        uint256 _averagePrice,
        uint256 _indexPrice,
        uint256 _nextSize,
        uint256 _delta,
        int256 _realisedPnl
    ) public pure returns (uint256) {
        (bool hasProfit, uint256 nextDelta) = _getNextDelta(_delta, _averagePrice, _indexPrice, _realisedPnl);
        uint256 nextAveragePrice = (_indexPrice
            * _nextSize)
            / (hasProfit ? _nextSize - nextDelta : _nextSize + nextDelta);

        return nextAveragePrice;
    }

    function _getNextDelta(
        uint256 _delta,
        uint256 _averagePrice,
        uint256 _indexPrice,
        int256 _realisedPnl
    ) internal pure returns (bool, uint256) {
        bool hasProfit = _averagePrice > _indexPrice;

        if (hasProfit) {
            // global shorts pnl is positive
            if (_realisedPnl > 0) {
                if (uint256(_realisedPnl) > _delta) {
                    _delta = uint256(_realisedPnl) - _delta;
                    hasProfit = false;
                } else {
                    _delta = _delta - uint256(_realisedPnl);
                }
            } else {
                _delta = _delta + uint256(-_realisedPnl);
            }

            return (hasProfit, _delta);
        }

        if (_realisedPnl > 0) {
            _delta = _delta + uint256(_realisedPnl);
        } else {
            if (uint256(-_realisedPnl) > _delta) {
                _delta = uint256(-_realisedPnl) - _delta;
                hasProfit = true;
            } else {
                _delta = _delta - uint256(-_realisedPnl);
            }
        }
        return (hasProfit, _delta);
    }

    function _getRealisedPnl(
        uint256 _sizeDelta,
        bool _isIncrease,
        Position memory _position
    ) internal view returns (int256) {
        if (_isIncrease) {
            return 0;
        }

        (bool hasProfit, uint256 delta) = priceManager.getDelta(
            _position.indexToken,
            _position.size,
            _position.averagePrice,
            _position.isLong, 
            0
        );
        // Get the proportional change in pnl
        uint256 adjustedDelta = (_sizeDelta * delta) / _position.size;
        require(adjustedDelta < uint256(type(int256).max), "Overflow");
        return hasProfit ? int256(adjustedDelta) : -int256(adjustedDelta);
    }
}
