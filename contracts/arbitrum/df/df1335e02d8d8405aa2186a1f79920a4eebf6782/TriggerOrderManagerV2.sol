// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./UUPSUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./IPriceManager.sol";
import "./ITriggerOrderManager.sol";
import "./IPositionRouterV2.sol";
import "./IPositionHandlerV2.sol";
import "./IPositionKeeperV2.sol";
import "./ISettingsManagerV2.sol";
import "./BasePositionV2.sol";

import {Constants} from "./Constants.sol";
import {Position, TriggerStatus, TriggerOrder} from "./Structs.sol";

contract TriggerOrderManagerV2 is ITriggerOrderManager, BasePositionV2, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    IPositionRouterV2 public positionRouter;
    mapping(bytes32 => TriggerOrder) public triggerOrders;
    uint256[50] private __gap;

    event FinalInitialized(
        address priceManager,
        address settingsManager,
        address positionHandler,
        address positionKeeper,
        address positionRouter
    );
    event ExecuteTriggerOrders(
        bytes32 key,
        uint256[] tpPrices,
        uint256[] slPrices,
        uint256[] tpAmountPercents,
        uint256[] slAmountPercents,
        uint256[] tpTriggeredAmounts,
        uint256[] slTriggeredAmounts,
        TriggerStatus status
    );
    event UpdateTriggerOrders(
        bytes32 key,
        uint256[] tpPrices,
        uint256[] slPrices,
        uint256[] tpAmountPercents,
        uint256[] slAmountPercents,
        uint256[] tpTriggeredAmounts,
        uint256[] slTriggeredAmounts,
        TriggerStatus status,
        bool isLastSynchronizePrice
    );
    event UpdateTriggerStatus(bytes32 key, TriggerStatus status);

    modifier onlyPositionaHandler() {
        require(msg.sender == address(positionHandler), "Forbidden: Not positionHandler");
        _;
    }

    function initialize(
        address _priceManager,
        address _settingsManager,
        address _positionHandler, 
        address _positionKeeper
    ) public initializer {
        _initialize(
            _priceManager,
            _settingsManager,
            _positionHandler, 
            _positionKeeper
        );
    }

    function finalInitialize(
        address _positionRouter
    ) public onlyOwner {
        require(AddressUpgradeable.isContract(_positionRouter), "Invalid positionRouter");
        positionRouter = IPositionRouterV2(_positionRouter);
        emit FinalInitialized(
            address(priceManager),
            address(settingsManager),
            address(positionHandler), 
            address(positionKeeper),
            _positionRouter
        );
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /*
    @dev: Trigger position, called by positionOwner.
        * Required isFastPrice = true then the process may work as trigger flow, otherwise revert.
    */
    function triggerPosition(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external nonReentrant {
        require(settingsManager.isTradable(_indexToken), "Invalid indexToken");
        _prevalidate(_indexToken);
        bytes32 key = _getPositionKey(_account, _indexToken, _isLong, _posId);
        (Position memory position, OrderInfo memory order) = positionKeeper.getPositions(key);
        require(msg.sender == position.owner, "Invalid positionOwner");
        address[] memory path;
        bool isFastExecute;
        uint256[] memory prices;
        uint256 txType;

        if (position.size == 0) {
            //Trigger for creating position
            PrepareTransaction memory txn = positionRouter.getTransaction(key);
            require(txn.status == TRANSACTION_STATUS_PENDING, "Invalid txStatus");
            txType = _getTxTypeFromPositionType(order.positionType);
            require(_isDelayPosition(txType), "Invalid delayOrder");
            path = positionRouter.getPath(key, txType);
            require(path.length > 0 && _indexToken == path[0], "Invalid indexToken");
            (isFastExecute, prices) = _getPricesAndCheckFastExecute(path);
            require(isFastExecute, "This delay position trigger has already pending to execute");
            require(positionRouter.getParams(key, txType).length > 0, "Invalid triggerParams");
        } else {
            //Trigger for addTrailingStop or updateTriggerOrders
            path = positionKeeper.getPositionFinalPath(key);
            (isFastExecute, prices) = _getPricesAndCheckFastExecute(path);
            require(isFastExecute, "This trigger has already pending to execute");
            txType = order.positionType == POSITION_TRAILING_STOP ? ADD_TRAILING_STOP : TRIGGER_POSITION;
        }

        require(path.length == prices.length && prices.length > 0, "Invalid prices"); 
        positionRouter.triggerPosition(
            key,
            txType,
            path,
            prices
        );
    }

    function cancelTriggerOrders(address _token, bool _isLong, uint256 _posId) external {
        bytes32 key = _getPositionKey(msg.sender, _token, _isLong, _posId);
        TriggerOrder storage order = triggerOrders[key];
        require(order.status == TriggerStatus.OPEN, "TriggerOrder was cancelled");
        order.status = TriggerStatus.CANCELLED;
        emit UpdateTriggerStatus(key, order.status);
    }

    function executeTriggerOrders(
        address _account,
        address _token,
        bool _isLong,
        uint256 _posId,
        uint256 _indexPrice
    ) external override onlyPositionaHandler returns (bool, uint256) {
        bytes32 key = _getPositionKey(_account, _token, _isLong, _posId);
        TriggerOrder storage order = triggerOrders[key];
        Position memory position = positionKeeper.getPosition(key);
        require(order.status == TriggerStatus.OPEN, "TriggerOrder not Open");
        uint256 price = _indexPrice == 0 ? priceManager.getLastPrice(_token) : _indexPrice;

        for (bool tp = true; ; tp = false) {
            uint256[] storage prices = tp ? order.tpPrices : order.slPrices;
            uint256[] storage triggeredAmounts = tp ? order.tpTriggeredAmounts : order.slTriggeredAmounts;
            uint256[] storage amountPercents = tp ? order.tpAmountPercents : order.slAmountPercents;
            uint256 closeAmountPercent;

            for (uint256 i = 0; i != prices.length && closeAmountPercent < BASIS_POINTS_DIVISOR; ++i) {
                bool pricesAreUpperBounds = tp ? _isLong : !_isLong;

                if (triggeredAmounts[i] == 0 && (pricesAreUpperBounds ? prices[i] <= price : price <= prices[i])) {
                    closeAmountPercent += amountPercents[i];
                    triggeredAmounts[i] = (position.size * amountPercents[i]) / BASIS_POINTS_DIVISOR;
                }
            }

            if (closeAmountPercent != 0) {
                emit ExecuteTriggerOrders(
                    key,
                    order.tpPrices,
                    order.slPrices,
                    order.tpAmountPercents,
                    order.slAmountPercents,
                    order.tpTriggeredAmounts,
                    order.slTriggeredAmounts,
                    order.status
                );

                if (closeAmountPercent >= BASIS_POINTS_DIVISOR) {
                    order.status = TriggerStatus.TRIGGERED;
                    return (true, BASIS_POINTS_DIVISOR);
                }
                
                return (true, closeAmountPercent);
            }

            if (!tp) {
                break;
            }
        }

        return (false, 0);
    }

    function updateTriggerOrders(
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256[] memory _tpPrices,
        uint256[] memory _slPrices,
        uint256[] memory _tpAmountPercents,
        uint256[] memory _slAmountPercents,
        uint256[] memory _tpTriggeredAmounts,
        uint256[] memory _slTriggeredAmounts
    ) external payable nonReentrant {
        bytes32 key = _getPositionKey(msg.sender, _indexToken, _isLong, _posId);
        Position memory position = positionKeeper.getPosition(msg.sender, _indexToken, _isLong, _posId);
        require(position.size > 0, "Zero positionSize");
        require(position.owner == msg.sender, "Invalid positionOwner");
        payable(settingsManager.getFeeManager()).transfer(msg.value);
        (bool isFastExecute, uint256 indexPrice) = _getPriceAndCheckFastExecute(_indexToken);
        require(_validateTriggerOrdersData(
                _isLong,
                indexPrice,
                _tpPrices,
                _slPrices,
                _tpTriggeredAmounts,
                _slTriggeredAmounts), 
        "Invalid triggerData");
        uint256 maxTriggerPriceLength = settingsManager.maxTriggerPriceLength();

        if (maxTriggerPriceLength > 0 && ((_tpPrices.length + _slPrices.length) > 0)) {
            require(_tpPrices.length + _slPrices.length
                <= maxTriggerPriceLength, "MaxTriggerPriceLength exceeded");
        }

        if (triggerOrders[key].tpPrices.length + triggerOrders[key].slPrices.length < _tpPrices.length + _slPrices.length) {
            require(msg.value == settingsManager.triggerGasFee(), "Invalid triggerGasFee");
        }

        triggerOrders[key] = TriggerOrder({
            key: key,
            isLong: _isLong,
            tpTriggeredAmounts: _tpTriggeredAmounts,
            slTriggeredAmounts: _slTriggeredAmounts,
            tpPrices: _tpPrices,
            tpAmountPercents: _tpAmountPercents,
            slPrices: _slPrices,
            slAmountPercents: _slAmountPercents,
            status: TriggerStatus.OPEN
        });

        emit UpdateTriggerOrders(
            key,
            _tpPrices,
            _slPrices,
            _tpAmountPercents,
            _slAmountPercents,
            _tpTriggeredAmounts,
            _slTriggeredAmounts,
            TriggerStatus.OPEN,
            isFastExecute
        );
    }

    function getTriggerOrderInfo(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) external view returns (TriggerOrder memory) {
        return _getTriggerOrderInfo(_getPositionKey(_account, _indexToken, _isLong, _posId));
    }

    function getTriggerOrderInfo(bytes32 _key) external view returns (TriggerOrder memory) {
        return _getTriggerOrderInfo(_key);
    }

    function _getTriggerOrderInfo(bytes32 _key) internal view returns (TriggerOrder memory) {
        return triggerOrders[_key];
    }

    function validateTPSLTriggers(
        bytes32 _key,
        uint256 _indexPrice
    ) external view override returns (bool) {
        return _validateTPSLTriggers(
            _key,
            _indexPrice
        );
    }

    function validateTPSLTriggers(
        address _account,
        address _token,
        bool _isLong,
        uint256 _posId,
        uint256 _indexPrice
    ) external view returns (bool) {
        return _validateTPSLTriggers(_getPositionKey(_account, _token, _isLong, _posId), _indexPrice);
    }

    function _validateTPSLTriggers(
        bytes32 _key,
        uint256 _indexPrice
    ) internal view returns (bool) {
        require(_indexPrice > 0, "Invalid indexPrice");
        (address owner, , bool isLong, ) = positionKeeper.getBasePosition(_key);
        require(owner != address(0), "Invalid pOwner");
        TriggerOrder storage order = triggerOrders[_key];

        if (order.status != TriggerStatus.OPEN) {
            return false;
        }

        for (bool tp = true; ; tp = false) {
            uint256[] storage prices = tp ? order.tpPrices : order.slPrices;
            uint256[] storage triggeredAmounts = tp ? order.tpTriggeredAmounts : order.slTriggeredAmounts;
            uint256[] storage amountPercents = tp ? order.tpAmountPercents : order.slAmountPercents;
            uint256 closeAmountPercent;
            
            for (uint256 i = 0; i != prices.length && closeAmountPercent < BASIS_POINTS_DIVISOR; ++i) {
                bool pricesAreUpperBounds = tp ? isLong : !isLong;
                
                if (triggeredAmounts[i] == 0 && (pricesAreUpperBounds ? prices[i] <= _indexPrice : _indexPrice <= prices[i])) {
                    closeAmountPercent += amountPercents[i];
                }
            }

            if (closeAmountPercent != 0) {
                return true;
            }

            if (!tp) {
                break;
            }
        }

        return false;
    }

    function validateTriggerOrdersData(
        bool _isLong,
        uint256 _indexPrice,
        uint256[] memory _tpPrices,
        uint256[] memory _slPrices,
        uint256[] memory _tpTriggeredAmounts,
        uint256[] memory _slTriggeredAmounts
    ) external pure returns (bool) {
        return _validateTriggerOrdersData(
            _isLong,
            _indexPrice,
            _tpPrices,
            _slPrices,
            _tpTriggeredAmounts,
            _slTriggeredAmounts
        );
    }

    function _validateTriggerOrdersData(
        bool _isLong,
        uint256 _indexPrice,
        uint256[] memory _tpPrices,
        uint256[] memory _slPrices,
        uint256[] memory _tpTriggeredAmounts,
        uint256[] memory _slTriggeredAmounts
    ) internal pure returns (bool) {
        for (bool tp = true; ; tp = false) {
            uint256[] memory prices = tp ? _tpPrices : _slPrices;
            uint256[] memory triggeredAmounts = tp ? _tpTriggeredAmounts : _slTriggeredAmounts;
            require(triggeredAmounts.length == prices.length, "Invalid price/triggeredAmount length");
            bool pricesAreUpperBounds = tp ? _isLong : !_isLong;
            uint256 sumPrice;

            for (uint256 i = 0; i < prices.length; ++i) {
                sumPrice += prices[i];

                if (triggeredAmounts[i] == 0 && (_indexPrice < prices[i]) != pricesAreUpperBounds) {
                    return false;
                }
            }

            //Validate if all prices duplicated
            if (prices.length > 1 && sumPrice > 0) {
                require(prices[0] * prices.length != sumPrice, "Invalid price");
            }

            if (!tp) {
                break;
            }
        }

        return true;
    }
}
