// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IERC20.sol";

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";

import "./WardedLivingUpgradeable.sol";
import "./IDefexaExchange.sol";

contract DefexaExchange is Initializable,
    UUPSUpgradeable, OwnableUpgradeable, WardedLivingUpgradeable,
    IDefexaExchange {

    // Order types
    uint8 constant ORDER_TYPE_GTC = 0;

    // Order statuses
    uint8 constant ORDER_STATUS_INVALID = 0;
    uint8 constant ORDER_STATUS_NEW = 1;
    uint8 constant ORDER_STATUS_CANCELLED = 2;
    uint8 constant ORDER_STATUS_FILLED = 3;
    uint8 constant ORDER_STATUS_PARTIALLY_FILLED = 4;

    mapping(uint256 => Order) public orders;

    uint256 public takerFee; //1e4; 100 means 1%; 10000 == 100%
    mapping(address => uint256) public feeGathered;

    address public feeCollector;

    // To generate unique order ids
    uint256 orderNonce;

    uint256 constant MAXIMUM_FEE = 1000;

    function initialize(
        address _feeCollector,
        uint256 _takerFee
    ) public initializer {
        __Ownable_init();
        __WardedLiving_init();

        if (_feeCollector == address(0)) {
            revert FeeCollectorAddressInvalid();
        }
        feeCollector = _feeCollector;
        if (_takerFee > MAXIMUM_FEE) {
            revert TakerFeeTooHigh(_takerFee);
        }
        takerFee = _takerFee;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    receive() external payable {}

    function createOrder(
        address _tokenA,
        address _tokenB,
        uint256 _amount,
        uint256 _price,
        bool _isQuote,
        uint8 _orderType
    ) external live payable override returns (uint256) {
        if (_tokenA == _tokenB) {
            revert TokensMismatch();
        }
        if (_orderType != ORDER_TYPE_GTC) {
            revert OrderTypeNotSupported(_orderType);
        }
        if (_amount == 0 || _price == 0) {
            revert InvalidOrder();
        }

        uint256 holdAmount = _amount;
        if (_isQuote) {
            holdAmount = _amount * _price / 1e18;
        }

        if (_tokenA == address(0) && msg.value != holdAmount) {
            revert InvalidOrder();
        }

        uint256 newId = uint256(keccak256(abi.encode(orderNonce, msg.sender, block.timestamp, _amount)));
        orderNonce++;

        orders[newId] = Order({
            id: newId,
            createdAt: block.timestamp,
            user: msg.sender,
            tokenA: _tokenA,
            tokenB: _tokenB,
            amount: _amount,
            initialAmount: holdAmount,
            spentAmount: 0,
            price: _price,
            isQuote: _isQuote,
            orderType: _orderType,
            status: ORDER_STATUS_NEW
        });

        if (_tokenA != address(0)) {
            if (!IERC20(_tokenA).transferFrom(msg.sender, address(this), holdAmount)) {
                revert TransferFailed();
            }
        }

        emit NewOrder(msg.sender, newId, _amount, _price, _tokenA, _tokenB, block.timestamp, _isQuote, _orderType);

        return newId;
    }

    function cancelOrder(
        uint256 _orderId
    ) external live override {
        _checkOrderIsActive(_orderId);
        if (orders[_orderId].user != msg.sender) {
            revert Forbidden();
        }

        orders[_orderId].status = ORDER_STATUS_CANCELLED;

        uint256 leftover = orders[_orderId].initialAmount - orders[_orderId].spentAmount;
        _send(msg.sender, orders[_orderId].tokenA, leftover);

        emit OrderCanceled(msg.sender, _orderId, block.timestamp);
    }

    function _fill(
        Order storage maker,
        Order storage taker
    ) internal {
        if (1e36 > maker.price * taker.price) {
            revert PriceMismatch(maker.price, taker.price);
        }

        (uint256 makerAmount, uint256 makerQuote, uint256 takerAmount, uint256 takerQuote) =
            _getAmountForPrice(maker, taker);
        if (makerQuote > takerAmount) {
            makerQuote = takerAmount;
        }
        if (takerQuote > makerAmount) {
            takerQuote = makerAmount;
        }
        uint256 takerToMaker = makerQuote;
        uint256 makerToTaker = takerQuote;

        if (maker.isQuote) {
            maker.amount -= takerToMaker;
        } else {
            maker.amount -= makerToTaker;
        }
        maker.spentAmount += makerToTaker;
        if (taker.isQuote) {
            taker.amount -= makerToTaker;
        } else {
            taker.amount -= takerToMaker;
        }
        taker.spentAmount += takerToMaker;

        _setOrderStatus(maker);
        _setOrderStatus(taker);

        uint256 fee = _takeFee(taker.id, makerToTaker, taker.user, taker.tokenB);
        _returnLeftover(taker);
        _returnLeftover(maker);

        _send(taker.user, maker.tokenA, makerToTaker - fee);
        _send(maker.user, taker.tokenA, takerToMaker);

        _emitOrderFilled(maker, makerToTaker, takerToMaker, 0);
        _emitOrderFilled(taker, takerToMaker, makerToTaker, fee);
    }


    // @dev
    // match taker order with makers
    // maker orders should be ordered from the best price to worse
    function matchOrders(
        uint256[] memory _makers,
        uint256 _takerId
    ) public override auth {
        if (orders[_takerId].createdAt == 0) {
            revert OrderNotFound(_takerId);
        }
        _checkOrderIsActive(_takerId);

        for (uint256 i = 0; i < _makers.length; i++) {
            Order storage taker = orders[_takerId];
            Order storage maker = orders[_makers[i]];
            if (maker.createdAt == 0) {
                revert OrderNotFound(_makers[i]);
            }
            _checkOrderIsActive(_makers[i]);

            if ((maker.tokenA != taker.tokenB) ||
                (maker.tokenB != taker.tokenA)) {
                revert TokensMismatch();
            }
            if (taker.amount == 0) {
                break;
            }
            _fill(maker, taker);
        }
    }

    // ADMIN

    function setTakerFee(uint256 _newFee) external auth {
        if (_newFee > MAXIMUM_FEE) {
            revert TakerFeeTooHigh(_newFee);
        }
        takerFee = _newFee;
        emit TakerFeeUpdated(_newFee, block.timestamp);
    }

    function setFeeCollector(address _feeCollector) external auth {
        if (_feeCollector == address(0)) {
            revert FeeCollectorAddressInvalid();
        }
        feeCollector = _feeCollector;
        emit FeeCollectorUpdated(feeCollector, block.timestamp);
    }

    function stopExchange() external auth {
        stop();
    }

    function startExchange() external auth {
        run();
    }

    // view

    function _getAmountForPrice(
        Order memory maker,
        Order memory taker
    ) internal pure returns(
        uint256 makerAmount, uint256 makerQuote, uint256 takerAmount, uint256 takerQuote) {
        takerQuote = taker.amount * maker.price / 1e18;
        makerQuote = maker.amount * 1e18 / maker.price;
        makerAmount = maker.amount;
        takerAmount = taker.amount;
        if (maker.isQuote) {
            makerQuote = maker.amount;
            makerAmount = maker.amount * maker.price / 1e18;
        }
        if (taker.isQuote) {
            takerQuote = taker.amount;
            takerAmount = taker.amount * 1e18 / maker.price;
        }
    }

    function _checkOrderIsActive(uint256 _orderId) internal view {
        if (
            orders[_orderId].status != ORDER_STATUS_NEW &&
            orders[_orderId].status != ORDER_STATUS_PARTIALLY_FILLED
        ) {
            revert OrderStatusInvalid(orders[_orderId].status);
        }
    }

    // internal

    function _send(address receiver, address token, uint256 amount) internal {
        if (token == address(0)) {
            payable(receiver).transfer(amount);
        } else {
            if (!IERC20(token).transfer(receiver, amount)) {
                revert TransferFailed();
            }
        }
    }

    function _returnLeftover(Order memory taker) internal returns(uint256 leftover) {
        leftover = 0;
        if (taker.isQuote && taker.amount == 0) {
            leftover = taker.initialAmount - taker.spentAmount;
            _send(taker.user, taker.tokenA, leftover);

            emit LeftoverReturned(taker.user, taker.id, taker.tokenA, leftover, block.timestamp);
        }
    }

    //
    /// @dev Gathers fee from the taker
    /// @return fee collected with 1e18 precision
    //
    function _takeFee(
        uint256 _orderId,
        uint256 _takerAmount,
        address _taker,
        address _token
    ) internal returns (uint256) {
        if (takerFee > 0) {
            uint256 fee = _takerAmount * takerFee / 1e4;
            feeGathered[_token] += fee;

            _send(feeCollector, _token, fee);

            emit FeeGathered(_taker, _orderId, _token, fee, block.timestamp);
            return fee;
        }
        return 0;
    }

    function _setOrderStatus(Order storage order) internal {
        if (order.amount == 0) {
            order.status = ORDER_STATUS_FILLED;
        } else {
            order.status = ORDER_STATUS_PARTIALLY_FILLED;
        }
    }

    function _emitOrderFilled(Order memory order, uint256 amountSent, uint256 amountReceived, uint256 fee) internal {
        if (order.amount == 0) {
            emit OrderFilled(order.id, amountSent, amountReceived, fee, block.timestamp);
        } else {
            emit OrderFilledPartially(order.id, amountSent, amountReceived - fee, block.timestamp);
        }
    }
}

