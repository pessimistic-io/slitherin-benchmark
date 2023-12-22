pragma solidity 0.7.6;
pragma abicoder v2;

// SPDX-License-Identifier: GPL-3.0-or-later
// Deployed with donations via Gitcoin GR9




import "./ITwapPair.sol";
import "./ITwapDelay.sol";
import "./IWETH.sol";
import "./SafeMath.sol";
import "./Orders.sol";
import "./TokenShares.sol";
import "./AddLiquidity.sol";
import "./WithdrawHelper.sol";
import "./ExecutionHelper.sol";
import "./ITwapFactoryGovernor.sol";


contract TwapDelay is ITwapDelay {
    using SafeMath for uint256;
    using Orders for Orders.Data;
    using TokenShares for TokenShares.Data;

    Orders.Data internal orders;
    TokenShares.Data internal tokenShares;

    uint256 private constant ORDER_CANCEL_TIME = 24 hours;
    uint256 private constant BOT_EXECUTION_TIME = 20 minutes;

    address public override owner;
    address public override factoryGovernor;
    address public constant RELAYER_ADDRESS = 0x3c6951FDB433b5b8442e7aa126D50fBFB54b5f42; 
    mapping(address => bool) public override isBot;

    constructor(address _factoryGovernor, address _bot) {
        _setOwner(msg.sender);
        _setFactoryGovernor(_factoryGovernor);
        _setBot(_bot, true);

        orders.gasPrice = tx.gasprice;
        _emitEventWithDefaults();
    }

    function getTransferGasCost(address token) external pure override returns (uint256 gasCost) {
        return Orders.getTransferGasCost(token);
    }

    function getDepositDisabled(address pair) external view override returns (bool) {
        return orders.getDepositDisabled(pair);
    }

    function getWithdrawDisabled(address pair) external view override returns (bool) {
        return orders.getWithdrawDisabled(pair);
    }

    function getBuyDisabled(address pair) external view override returns (bool) {
        return orders.getBuyDisabled(pair);
    }

    function getSellDisabled(address pair) external view override returns (bool) {
        return orders.getSellDisabled(pair);
    }

    function getOrderStatus(uint256 orderId, uint256 validAfterTimestamp)
        external
        view
        override
        returns (Orders.OrderStatus)
    {
        return orders.getOrderStatus(orderId, validAfterTimestamp);
    }

    uint256 private locked;
    modifier lock() {
        require(locked == 0, 'TD06');
        locked = 1;
        _;
        locked = 0;
    }

    function factory() external pure override returns (address) {
        return Orders.FACTORY_ADDRESS;
    }

    function totalShares(address token) external view override returns (uint256) {
        return tokenShares.totalShares[token];
    }

    // returns wrapped native currency for particular blockchain (WETH or WMATIC)
    function weth() external pure override returns (address) {
        return TokenShares.WETH_ADDRESS;
    }

    function relayer() external pure override returns (address) {
        return RELAYER_ADDRESS;
    }

    function isNonRebasingToken(address token) external pure override returns (bool) {
        return TokenShares.isNonRebasing(token);
    }

    function delay() external pure override returns (uint256) {
        return Orders.DELAY;
    }

    function lastProcessedOrderId() external view returns (uint256) {
        return orders.lastProcessedOrderId;
    }

    function newestOrderId() external view returns (uint256) {
        return orders.newestOrderId;
    }

    function isOrderCanceled(uint256 orderId) external view returns (bool) {
        return orders.canceled[orderId];
    }

    function maxGasLimit() external pure override returns (uint256) {
        return Orders.MAX_GAS_LIMIT;
    }

    function maxGasPriceImpact() external pure override returns (uint256) {
        return Orders.MAX_GAS_PRICE_IMPACT;
    }

    function gasPriceInertia() external pure override returns (uint256) {
        return Orders.GAS_PRICE_INERTIA;
    }

    function gasPrice() external view override returns (uint256) {
        return orders.gasPrice;
    }

    function setOrderTypesDisabled(
        address pair,
        Orders.OrderType[] calldata orderTypes,
        bool disabled
    ) external override {
        require(msg.sender == owner, 'TD00');
        orders.setOrderTypesDisabled(pair, orderTypes, disabled);
    }

    function setOwner(address _owner) external override {
        require(msg.sender == owner, 'TD00');
        _setOwner(_owner);
    }

    function _setOwner(address _owner) internal {
        require(_owner != owner, 'TD01');
        require(_owner != address(0), 'TD02');
        owner = _owner;
        emit OwnerSet(_owner);
    }

    function setFactoryGovernor(address _factoryGovernor) external override {
        require(msg.sender == owner, 'TD00');
        _setFactoryGovernor(_factoryGovernor);
    }

    function _setFactoryGovernor(address _factoryGovernor) internal {
        require(_factoryGovernor != factoryGovernor, 'TD01');
        require(_factoryGovernor != address(0), 'TD02');
        factoryGovernor = _factoryGovernor;
        emit FactoryGovernorSet(_factoryGovernor);
    }

    function setBot(address _bot, bool _isBot) external override {
        require(msg.sender == owner, 'TD00');
        _setBot(_bot, _isBot);
    }

    function _setBot(address _bot, bool _isBot) internal {
        require(_isBot != isBot[_bot], 'TD01');
        isBot[_bot] = _isBot;
        emit BotSet(_bot, _isBot);
    }

    function deposit(Orders.DepositParams calldata depositParams)
        external
        payable
        override
        lock
        returns (uint256 orderId)
    {
        orders.deposit(depositParams, tokenShares);
        return orders.newestOrderId;
    }

    function withdraw(Orders.WithdrawParams calldata withdrawParams)
        external
        payable
        override
        lock
        returns (uint256 orderId)
    {
        orders.withdraw(withdrawParams);
        return orders.newestOrderId;
    }

    function sell(Orders.SellParams calldata sellParams) external payable override lock returns (uint256 orderId) {
        orders.sell(sellParams, tokenShares);
        return orders.newestOrderId;
    }

    function relayerSell(Orders.SellParams calldata sellParams)
        external
        payable
        override
        lock
        returns (uint256 orderId)
    {
        require(msg.sender == RELAYER_ADDRESS, 'TD00');
        orders.relayerSell(sellParams, tokenShares);
        return orders.newestOrderId;
    }

    function buy(Orders.BuyParams calldata buyParams) external payable override lock returns (uint256 orderId) {
        orders.buy(buyParams, tokenShares);
        return orders.newestOrderId;
    }

    /// @dev This implementation processes orders sequentially and skips orders that have already been executed.
    /// If it encounters an order that is not yet valid, it stops execution since subsequent orders will also be invalid
    /// at the time.
    function execute(Orders.Order[] calldata _orders) external payable override lock {
        uint256 ordersLength = _orders.length;
        uint256 gasBefore = gasleft();
        bool orderExecuted;
        bool senderCanExecute = isBot[msg.sender] || isBot[address(0)];
        for (uint256 i; i < ordersLength; ++i) {
            if (_orders[i].orderId <= orders.lastProcessedOrderId) {
                continue;
            }
            if (orders.canceled[_orders[i].orderId]) {
                orders.dequeueOrder(_orders[i].orderId);
                continue;
            }
            orders.verifyOrder(_orders[i]);
            uint256 validAfterTimestamp = _orders[i].validAfterTimestamp;
            if (validAfterTimestamp >= block.timestamp) {
                break;
            }
            require(senderCanExecute || block.timestamp >= validAfterTimestamp + BOT_EXECUTION_TIME, 'TD00');
            orderExecuted = true;
            if (_orders[i].orderType == Orders.OrderType.Deposit) {
                executeDeposit(_orders[i]);
            } else if (_orders[i].orderType == Orders.OrderType.Withdraw) {
                executeWithdraw(_orders[i]);
            } else if (_orders[i].orderType == Orders.OrderType.Sell) {
                executeSell(_orders[i]);
            } else if (_orders[i].orderType == Orders.OrderType.Buy) {
                executeBuy(_orders[i]);
            }
        }
        if (orderExecuted) {
            orders.updateGasPrice(gasBefore.sub(gasleft()));
        }
    }

    /// @dev The `order` must be verified by calling `Orders.verifyOrder` before calling this function.
    function executeDeposit(Orders.Order calldata order) internal {
        uint256 gasStart = gasleft();
        orders.dequeueOrder(order.orderId);

        (bool executionSuccess, bytes memory data) = address(this).call{
            gas: order.gasLimit.sub(
                Orders.ORDER_BASE_COST.add(Orders.getTransferGasCost(order.token0)).add(
                    Orders.getTransferGasCost(order.token1)
                )
            )
        }(abi.encodeWithSelector(this._executeDeposit.selector, order));

        bool refundSuccess = true;
        if (!executionSuccess) {
            refundSuccess = refundTokens(
                order.to,
                order.token0,
                order.value0,
                order.token1,
                order.value1,
                order.unwrap
            );
        }
        finalizeOrder(refundSuccess);
        (uint256 gasUsed, uint256 ethRefund) = refund(order.gasLimit, order.gasPrice, gasStart, order.to);
        emit OrderExecuted(orders.lastProcessedOrderId, executionSuccess, data, gasUsed, ethRefund);
    }

    /// @dev The `order` must be verified by calling `Orders.verifyOrder` before calling this function.
    function executeWithdraw(Orders.Order calldata order) internal {
        uint256 gasStart = gasleft();
        orders.dequeueOrder(order.orderId);

        (bool executionSuccess, bytes memory data) = address(this).call{
            gas: order.gasLimit.sub(Orders.ORDER_BASE_COST.add(Orders.PAIR_TRANSFER_COST))
        }(abi.encodeWithSelector(this._executeWithdraw.selector, order));

        bool refundSuccess = true;
        if (!executionSuccess) {
            (address pair, ) = Orders.getPair(order.token0, order.token1);
            refundSuccess = Orders.refundLiquidity(pair, order.to, order.liquidity, this._refundLiquidity.selector);
        }
        finalizeOrder(refundSuccess);
        (uint256 gasUsed, uint256 ethRefund) = refund(order.gasLimit, order.gasPrice, gasStart, order.to);
        emit OrderExecuted(orders.lastProcessedOrderId, executionSuccess, data, gasUsed, ethRefund);
    }

    /// @dev The `order` must be verified by calling `Orders.verifyOrder` before calling this function.
    function executeSell(Orders.Order calldata order) internal {
        uint256 gasStart = gasleft();
        orders.dequeueOrder(order.orderId);

        (bool executionSuccess, bytes memory data) = address(this).call{
            gas: order.gasLimit.sub(Orders.ORDER_BASE_COST.add(Orders.getTransferGasCost(order.token0)))
        }(abi.encodeWithSelector(this._executeSell.selector, order));

        bool refundSuccess = true;
        if (!executionSuccess) {
            refundSuccess = refundToken(order.token0, order.to, order.value0, order.unwrap);
        }
        finalizeOrder(refundSuccess);
        (uint256 gasUsed, uint256 ethRefund) = refund(order.gasLimit, order.gasPrice, gasStart, order.to);
        emit OrderExecuted(orders.lastProcessedOrderId, executionSuccess, data, gasUsed, ethRefund);
    }

    /// @dev The `order` must be verified by calling `Orders.verifyOrder` before calling this function.
    function executeBuy(Orders.Order calldata order) internal {
        uint256 gasStart = gasleft();
        orders.dequeueOrder(order.orderId);

        (bool executionSuccess, bytes memory data) = address(this).call{
            gas: order.gasLimit.sub(Orders.ORDER_BASE_COST.add(Orders.getTransferGasCost(order.token0)))
        }(abi.encodeWithSelector(this._executeBuy.selector, order));

        bool refundSuccess = true;
        if (!executionSuccess) {
            refundSuccess = refundToken(order.token0, order.to, order.value0, order.unwrap);
        }
        finalizeOrder(refundSuccess);
        (uint256 gasUsed, uint256 ethRefund) = refund(order.gasLimit, order.gasPrice, gasStart, order.to);
        emit OrderExecuted(orders.lastProcessedOrderId, executionSuccess, data, gasUsed, ethRefund);
    }

    function finalizeOrder(bool refundSuccess) private {
        if (!refundSuccess) {
            orders.markRefundFailed();
        } else {
            orders.forgetLastProcessedOrder();
        }
    }

    function refund(
        uint256 gasLimit,
        uint256 gasPriceInOrder,
        uint256 gasStart,
        address to
    ) private returns (uint256 gasUsed, uint256 leftOver) {
        uint256 feeCollected = gasLimit.mul(gasPriceInOrder);
        gasUsed = gasStart.sub(gasleft()).add(Orders.REFUND_BASE_COST);
        uint256 actualRefund = Math.min(feeCollected, gasUsed.mul(orders.gasPrice));
        leftOver = feeCollected.sub(actualRefund);
        require(refundEth(msg.sender, actualRefund), 'TD40');
        refundEth(payable(to), leftOver);
    }

    function refundEth(address payable to, uint256 value) internal returns (bool success) {
        if (value == 0) {
            return true;
        }
        success = TransferHelper.transferETH(to, value, Orders.getTransferGasCost(Orders.NATIVE_CURRENCY_SENTINEL));
        emit EthRefund(to, success, value);
    }

    function refundToken(
        address token,
        address to,
        uint256 share,
        bool unwrap
    ) private returns (bool) {
        if (share == 0) {
            return true;
        }
        (bool success, bytes memory data) = address(this).call{ gas: Orders.getTransferGasCost(token) }(
            abi.encodeWithSelector(this._refundToken.selector, token, to, share, unwrap)
        );
        if (!success) {
            emit Orders.RefundFailed(to, token, share, data);
        }
        return success;
    }

    function refundTokens(
        address to,
        address token0,
        uint256 share0,
        address token1,
        uint256 share1,
        bool unwrap
    ) private returns (bool) {
        (bool success, bytes memory data) = address(this).call{
            gas: Orders.getTransferGasCost(token0).add(Orders.getTransferGasCost(token1))
        }(abi.encodeWithSelector(this._refundTokens.selector, to, token0, share0, token1, share1, unwrap));
        if (!success) {
            emit Orders.RefundFailed(to, token0, share0, data);
            emit Orders.RefundFailed(to, token1, share1, data);
        }
        return success;
    }

    function _refundTokens(
        address to,
        address token0,
        uint256 share0,
        address token1,
        uint256 share1,
        bool unwrap
    ) external payable {
        // no need to check sender, because it is checked in _refundToken
        _refundToken(token0, to, share0, unwrap);
        _refundToken(token1, to, share1, unwrap);
    }

    function _refundToken(
        address token,
        address to,
        uint256 share,
        bool unwrap
    ) public payable {
        require(msg.sender == address(this), 'TD00');
        if (token == TokenShares.WETH_ADDRESS && unwrap) {
            uint256 amount = tokenShares.sharesToAmount(token, share, 0, to);
            IWETH(TokenShares.WETH_ADDRESS).withdraw(amount);
            TransferHelper.safeTransferETH(to, amount, Orders.getTransferGasCost(Orders.NATIVE_CURRENCY_SENTINEL));
        } else {
            TransferHelper.safeTransfer(token, to, tokenShares.sharesToAmount(token, share, 0, to));
        }
    }

    function _refundLiquidity(
        address pair,
        address to,
        uint256 liquidity
    ) external payable {
        require(msg.sender == address(this), 'TD00');
        return TransferHelper.safeTransfer(pair, to, liquidity);
    }

    function _executeDeposit(Orders.Order calldata order) external payable {
        require(msg.sender == address(this), 'TD00');

        (address pairAddress, ) = Orders.getPair(order.token0, order.token1);

        ITwapPair(pairAddress).sync();
        ITwapFactoryGovernor(factoryGovernor).distributeFees(order.token0, order.token1, pairAddress);
        ITwapPair(pairAddress).sync();
        ExecutionHelper.executeDeposit(order, pairAddress, getTolerance(pairAddress), tokenShares);
    }

    function _executeWithdraw(Orders.Order calldata order) external payable {
        require(msg.sender == address(this), 'TD00');

        (address pairAddress, ) = Orders.getPair(order.token0, order.token1);

        ITwapPair(pairAddress).sync();
        ITwapFactoryGovernor(factoryGovernor).distributeFees(order.token0, order.token1, pairAddress);
        ITwapPair(pairAddress).sync();
        ExecutionHelper.executeWithdraw(order);
    }

    function _executeBuy(Orders.Order calldata order) external payable {
        require(msg.sender == address(this), 'TD00');

        (address pairAddress, ) = Orders.getPair(order.token0, order.token1);
        ExecutionHelper.ExecuteBuySellParams memory orderParams;
        orderParams.order = order;
        orderParams.pairAddress = pairAddress;
        orderParams.pairTolerance = getTolerance(pairAddress);

        ITwapPair(pairAddress).sync();
        ExecutionHelper.executeBuy(orderParams, tokenShares);
    }

    function _executeSell(Orders.Order calldata order) external payable {
        require(msg.sender == address(this), 'TD00');

        (address pairAddress, ) = Orders.getPair(order.token0, order.token1);
        ExecutionHelper.ExecuteBuySellParams memory orderParams;
        orderParams.order = order;
        orderParams.pairAddress = pairAddress;
        orderParams.pairTolerance = getTolerance(pairAddress);

        ITwapPair(pairAddress).sync();
        ExecutionHelper.executeSell(orderParams, tokenShares);
    }

    /// @dev The `order` must be verified by calling `Orders.verifyOrder` before calling this function.
    function performRefund(Orders.Order calldata order, bool shouldRefundEth) internal {
        bool canOwnerRefund = order.validAfterTimestamp.add(365 days) < block.timestamp;

        if (order.orderType == Orders.OrderType.Deposit) {
            address to = canOwnerRefund ? owner : order.to;
            require(refundTokens(to, order.token0, order.value0, order.token1, order.value1, order.unwrap), 'TD14');
            if (shouldRefundEth) {
                require(refundEth(payable(to), order.gasPrice.mul(order.gasLimit)), 'TD40');
            }
        } else if (order.orderType == Orders.OrderType.Withdraw) {
            (address pair, ) = Orders.getPair(order.token0, order.token1);
            address to = canOwnerRefund ? owner : order.to;
            require(Orders.refundLiquidity(pair, to, order.liquidity, this._refundLiquidity.selector), 'TD14');
            if (shouldRefundEth) {
                require(refundEth(payable(to), order.gasPrice.mul(order.gasLimit)), 'TD40');
            }
        } else if (order.orderType == Orders.OrderType.Sell) {
            address to = canOwnerRefund ? owner : order.to;
            require(refundToken(order.token0, to, order.value0, order.unwrap), 'TD14');
            if (shouldRefundEth) {
                require(refundEth(payable(to), order.gasPrice.mul(order.gasLimit)), 'TD40');
            }
        } else if (order.orderType == Orders.OrderType.Buy) {
            address to = canOwnerRefund ? owner : order.to;
            require(refundToken(order.token0, to, order.value0, order.unwrap), 'TD14');
            if (shouldRefundEth) {
                require(refundEth(payable(to), order.gasPrice.mul(order.gasLimit)), 'TD40');
            }
        } else {
            return;
        }
        orders.forgetOrder(order.orderId);
    }

    function retryRefund(Orders.Order calldata order) external override lock {
        orders.verifyOrder(order);
        require(orders.refundFailed[order.orderId], 'TD21');
        performRefund(order, false);
    }

    function cancelOrder(Orders.Order calldata order) external override lock {
        orders.verifyOrder(order);
        require(
            orders.getOrderStatus(order.orderId, order.validAfterTimestamp) == Orders.OrderStatus.EnqueuedReady,
            'TD52'
        );
        require(order.validAfterTimestamp.sub(Orders.DELAY).add(ORDER_CANCEL_TIME) < block.timestamp, 'TD1C');
        orders.canceled[order.orderId] = true;
        performRefund(order, true);
    }

    function syncPair(address token0, address token1) external override returns (address pairAddress) {
        require(msg.sender == factoryGovernor, 'TD00');

        (pairAddress, ) = Orders.getPair(token0, token1);
        ITwapPair(pairAddress).sync();
    }

    
    function _emitEventWithDefaults() internal {
        emit MaxGasLimitSet(Orders.MAX_GAS_LIMIT);
        emit GasPriceInertiaSet(Orders.GAS_PRICE_INERTIA);
        emit MaxGasPriceImpactSet(Orders.MAX_GAS_PRICE_IMPACT);
        emit DelaySet(Orders.DELAY);
        emit RelayerSet(RELAYER_ADDRESS);

        emit ToleranceSet(0x12b8bC27Ca8A997680F49d1A6FC1D93D552aacbe, 0);
        emit ToleranceSet(0x4BCa34ad27Df83566016B55c60Dd80a9eB14913b, 0);
        emit ToleranceSet(0xf31778748B3364fC43d6ab6AAc4f52E2C29B6353, 0);
        emit ToleranceSet(0x7A0f899EF730FE178E0574B8DAb4440cA336e415, 0);

        emit TransferGasCostSet(Orders.NATIVE_CURRENCY_SENTINEL, Orders.ETHER_TRANSFER_CALL_COST);
        emit TransferGasCostSet(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, 60000);
        emit TransferGasCostSet(0xaf88d065e77c8cC2239327C5EDb3A432268e5831, 70000);
        emit TransferGasCostSet(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8, 70000);
        emit TransferGasCostSet(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9, 60000);
        emit TransferGasCostSet(0x5979D7b546E38E414F7E9822514be443A4800529, 60000);

        emit NonRebasingTokenSet(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, true);
        emit NonRebasingTokenSet(0xaf88d065e77c8cC2239327C5EDb3A432268e5831, true);
        emit NonRebasingTokenSet(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8, true);
        emit NonRebasingTokenSet(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9, true);
        emit NonRebasingTokenSet(0x5979D7b546E38E414F7E9822514be443A4800529, true);
    }

    
    // constant mapping for tolerance
    function getTolerance(address) public virtual view override returns (uint16 tolerance) {
        return 0;
    }

    receive() external payable {}
}

