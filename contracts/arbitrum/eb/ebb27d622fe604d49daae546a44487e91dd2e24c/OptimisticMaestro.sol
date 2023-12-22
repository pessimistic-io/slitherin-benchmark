//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "./Maestro.sol";

// struct TradeParams {
//     PositionId positionId;
//     int256 quantity;
//     uint256 limitPrice; // in quote currency
//     Currency cashflowCcy;
//     int256 cashflow;
// }

// struct ExecutionParams {
//     Dex dex;
//     uint256 swapAmount;
//     bytes swapBytes;
//     FlashLoanProvider flashLoanProvider;
// }

// struct EIP2098Permit {
//     uint256 amount;
//     uint256 deadline;
//     bytes32 r;
//     bytes32 vs;
// }

library OptimisticCodec {
    function encodeAddressAndAmount(address token, uint256 amount) internal pure returns (bytes32 data) {
        require(amount <= type(uint96).max);
        return bytes32(bytes20(token)) | bytes32(amount);
    }

    function decodeAddressAndAmount(bytes32 deposit) internal pure returns (address token, uint256 amount) {
        token = address(bytes20(deposit));
        amount = uint96(uint256(deposit));
    }

    function encodeDepositWithPermit(IERC20Permit token, EIP2098Permit memory permit)
        internal
        pure
        returns (bytes32 data, bytes32 r, bytes32 vs)
    {
        require(permit.deadline == type(uint32).max);
        return (encodeAddressAndAmount(address(token), permit.amount), permit.r, permit.vs);
    }

    function decodeDepositWithPermit(bytes32 deposit, bytes32 r, bytes32 vs)
        internal
        pure
        returns (IERC20Permit token, EIP2098Permit memory permit)
    {
        (address _token, uint256 amount) = decodeAddressAndAmount(deposit);
        token = IERC20Permit(_token);
        permit.amount = amount;
        permit.deadline = type(uint32).max;
        permit.r = r;
        permit.vs = vs;
    }

    function encodeTrade(TradeParams memory tradeParams, ExecutionParams memory execParams)
        internal
        pure
        returns (bytes32 data1, bytes32 data2, bytes32 data3, bytes memory swapBytes)
    {
        require(int96(tradeParams.quantity) == tradeParams.quantity, "quantity");
        require(uint96(tradeParams.limitPrice) == tradeParams.limitPrice, "limitPrice");
        require(int96(tradeParams.cashflow) == tradeParams.cashflow, "cashflow");
        require(uint96(execParams.swapAmount) == execParams.swapAmount, "swapAmount");

        data1 = PositionId.unwrap(tradeParams.positionId);
        data2 = bytes32(bytes1(uint8(tradeParams.cashflowCcy))) | bytes32(bytes1(Dex.unwrap(execParams.dex))) >> 8
            | bytes32(bytes1(FlashLoanProvider.unwrap(execParams.flashLoanProvider))) >> 16
            | (bytes32(uint256(uint96(int96(tradeParams.quantity)))) << 96) | bytes32(tradeParams.limitPrice);
        data3 = (bytes32(uint256(uint96(int96(tradeParams.cashflow)))) << 96) | bytes32(execParams.swapAmount);

        swapBytes = execParams.swapBytes;
    }

    function decodeTrade(bytes32 data1, bytes32 data2, bytes32 data3, bytes memory swapBytes)
        internal
        pure
        returns (TradeParams memory tradeParams, ExecutionParams memory execParams)
    {
        tradeParams.positionId = PositionId.wrap(data1);
        tradeParams.quantity = int96(uint96(uint256(data2 >> 96)));
        tradeParams.limitPrice = uint96(uint256(data2));
        tradeParams.cashflowCcy = Currency(uint8(bytes1(data2)));
        tradeParams.cashflow = int96(uint96(uint256(data3 >> 96)));
        execParams.dex = Dex.wrap(uint8(bytes1(data2 << 8)));
        execParams.swapAmount = uint96(uint256(data3));
        execParams.swapBytes = swapBytes;
        execParams.flashLoanProvider = FlashLoanProvider.wrap(uint8(bytes1(data2 << 16)));
    }
}

contract OptimisticMaestro is Maestro {
    using OptimisticCodec for bytes32;

    constructor(address _timelock, IContango _contango, IOrderManager _orderManager, IVault _vault, IPermit2 _permit2)
        Maestro(_timelock, _contango, _orderManager, _vault, _permit2)
    {}

    function deposit(bytes32 data) public returns (uint256) {
        (address token, uint256 amount) = data.decodeAddressAndAmount();
        return super.deposit(IERC20(token), amount);
    }

    function depositWithPermit(bytes32 data, bytes32 r, bytes32 vs) public returns (uint256) {
        (IERC20Permit token, EIP2098Permit memory permit) = data.decodeDepositWithPermit(r, vs);
        return super.depositWithPermit(token, permit);
    }

    function depositWithPermit2(bytes32 data, bytes32 r, bytes32 vs) public returns (uint256) {
        (IERC20Permit token, EIP2098Permit memory permit) = data.decodeDepositWithPermit(r, vs);
        return super.depositWithPermit2(IERC20(address(token)), permit);
    }

    function withdraw(bytes32 data, address to) public returns (uint256) {
        (address token, uint256 amount) = data.decodeAddressAndAmount();
        return super.withdraw(IERC20(token), amount, to);
    }

    function withdrawNative(bytes32 data) public returns (uint256) {
        (address to, uint256 amount) = data.decodeAddressAndAmount();
        return super.withdrawNative(amount, to);
    }

    function trade(bytes32 data1, bytes32 data2, bytes32 data3, bytes memory swapBytes)
        public
        returns (PositionId, Trade memory)
    {
        (TradeParams memory tradeParams, ExecutionParams memory execParams) =
            OptimisticCodec.decodeTrade(data1, data2, data3, swapBytes);
        return super.trade(tradeParams, execParams);
    }

    function depositAndTrade(bytes32 data1, bytes32 data2, bytes32 data3, bytes memory swapBytes)
        public
        payable
        returns (PositionId, Trade memory)
    {
        (TradeParams memory tradeParams, ExecutionParams memory execParams) =
            OptimisticCodec.decodeTrade(data1, data2, data3, swapBytes);
        return super.depositAndTrade(tradeParams, execParams);
    }

    function depositAndTradeWithPermit(
        bytes32 data1,
        bytes32 data2,
        bytes32 data3,
        bytes memory swapBytes,
        bytes32 r,
        bytes32 vs
    ) public returns (PositionId, Trade memory) {
        (TradeParams memory tradeParams, ExecutionParams memory execParams) =
            OptimisticCodec.decodeTrade(data1, data2, data3, swapBytes);

        Instrument memory instrument = contango.instrument(tradeParams.positionId.getSymbol());
        IERC20Permit cashflowToken =
            IERC20Permit(address(tradeParams.cashflowCcy.isBase() ? instrument.base : instrument.quote));

        depositWithPermit(
            cashflowToken,
            EIP2098Permit({amount: uint256(tradeParams.cashflow), deadline: type(uint32).max, r: r, vs: vs})
        );
        return trade(tradeParams, execParams);
    }

    // function tradeAndWithdraw(TradeParams calldata tradeParams, ExecutionParams calldata execParams, address to)
    //     public
    //     returns (PositionId positionId, Trade memory trade_, uint256 amount)
    // {
    //     return _tradeAndWithdraw(tradeParams, execParams, to, false);
    // }

    // function tradeAndWithdrawNative(TradeParams calldata tradeParams, ExecutionParams calldata execParams, address to)
    //     public
    //     returns (PositionId positionId, Trade memory trade_, uint256 amount)
    // {
    //     return _tradeAndWithdraw(tradeParams, execParams, to, true);
    // }

    // function _tradeAndWithdraw(
    //     TradeParams calldata tradeParams,
    //     ExecutionParams calldata execParams,
    //     address to,
    //     bool native
    // ) public returns (PositionId positionId, Trade memory trade_, uint256 amount) {
    //     // require(tradeParams.cashflow < 0); // TODO do properly
    //     (positionId, trade_) = trade(tradeParams, execParams);
    //     amount = trade_.cashflow.abs();

    //     Instrument memory instrument = contango.instrument(positionId.getSymbol());
    //     IERC20 cashflowToken = trade_.cashflowCcy.isBase() ? instrument.base : instrument.quote;

    //     if (native) {
    //         if (nativeToken != cashflowToken) revert NotNativeToken(cashflowToken);
    //         withdrawNative(amount, to);
    //     } else {
    //         withdraw(cashflowToken, amount, to);
    //     }
    // }

    // function depositTradeAndLinkedOrder(
    //     TradeParams calldata tradeParams,
    //     ExecutionParams calldata execParams,
    //     LinkedOrderParams memory linkedOrderParams
    // ) public payable  returns (PositionId positionId, Trade memory trade_, OrderId linkedOrderId) {
    //     (positionId, trade_) = depositAndTrade(tradeParams, execParams);
    //     linkedOrderParams.positionId = positionId;
    //     linkedOrderId = placeLinkedOrder(linkedOrderParams);
    // }

    // function depositTradeAndLinkedOrderWithPermit(
    //     TradeParams calldata tradeParams,
    //     ExecutionParams calldata execParams,
    //     LinkedOrderParams memory linkedOrderParams,
    //     EIP2098Permit calldata permit
    // ) public  returns (PositionId positionId, Trade memory trade_, OrderId linkedOrderId) {
    //     (positionId, trade_) = depositAndTradeWithPermit(tradeParams, execParams, permit);
    //     linkedOrderParams.positionId = positionId;
    //     linkedOrderId = placeLinkedOrder(linkedOrderParams);
    // }

    // function depositTradeAndLinkedOrders(
    //     TradeParams calldata tradeParams,
    //     ExecutionParams calldata execParams,
    //     LinkedOrderParams memory linkedOrderParams1,
    //     LinkedOrderParams memory linkedOrderParams2
    // )
    //     public
    //     payable
    //
    //     returns (PositionId positionId, Trade memory trade_, OrderId linkedOrderId1, OrderId linkedOrderId2)
    // {
    //     (positionId, trade_) = depositAndTrade(tradeParams, execParams);

    //     linkedOrderParams1.positionId = positionId;
    //     linkedOrderParams2.positionId = positionId;

    //     linkedOrderId1 = placeLinkedOrder(linkedOrderParams1);
    //     linkedOrderId2 = placeLinkedOrder(linkedOrderParams2);
    // }

    // function depositTradeAndLinkedOrdersWithPermit(
    //     TradeParams calldata tradeParams,
    //     ExecutionParams calldata execParams,
    //     LinkedOrderParams memory linkedOrderParams1,
    //     LinkedOrderParams memory linkedOrderParams2,
    //     EIP2098Permit calldata permit
    // )
    //     public
    //
    //     returns (PositionId positionId, Trade memory trade_, OrderId linkedOrderId1, OrderId linkedOrderId2)
    // {
    //     (positionId, trade_) = depositAndTradeWithPermit(tradeParams, execParams, permit);

    //     linkedOrderParams1.positionId = positionId;
    //     linkedOrderParams2.positionId = positionId;

    //     linkedOrderId1 = placeLinkedOrder(linkedOrderParams1);
    //     linkedOrderId2 = placeLinkedOrder(linkedOrderParams2);
    // }

    // function place(OrderParams memory params) public  returns (OrderId orderId) {
    //     if (positionNFT.exists(params.positionId)) positionNFT.validateModifyPositionPermissions(params.positionId);

    //     return orderManager.placeOnBehalfOf(params, msg.sender);
    // }

    // function placeLinkedOrder(LinkedOrderParams memory params) public  returns (OrderId orderId) {
    //     positionNFT.validateModifyPositionPermissions(params.positionId);

    //     return orderManager.placeOnBehalfOf(
    //         OrderParams({
    //             positionId: params.positionId,
    //             quantity: type(int128).min,
    //             limitPrice: params.limitPrice,
    //             tolerance: params.tolerance,
    //             cashflow: 0,
    //             cashflowCcy: params.cashflowCcy,
    //             deadline: params.deadline,
    //             orderType: params.orderType
    //         }),
    //         msg.sender
    //     );
    // }

    // function depositAndPlace(OrderParams memory params) public payable  returns (OrderId orderId) {
    //     Instrument memory instrument = contango.instrument(params.positionId.getSymbol());
    //     IERC20 cashflowToken = params.cashflowCcy.isBase() ? instrument.base : instrument.quote;
    //     _deposit(cashflowToken, int256(params.cashflow).toUint256());
    //     return place(params);
    // }

    // function depositAndPlaceWithPermit(OrderParams memory params, EIP2098Permit calldata permit)
    //     public
    //     returns (OrderId orderId)
    // {
    //     // require(params.cashflow > 0 && int256(permit.amount) > params.cashflow); // TODO do properly
    //     Instrument memory instrument = contango.instrument(params.positionId.getSymbol());
    //     IERC20Permit cashflowToken =
    //         IERC20Permit(address(params.cashflowCcy.isBase() ? instrument.base : instrument.quote));

    //     depositWithPermit(cashflowToken, permit);
    //     return place(params);
    // }

    // function cancel(OrderId orderId) public {
    //     if (!positionNFT.isApprovedForAll(orderManager.orders(orderId).owner, msg.sender)) {
    //         revert Unauthorised(msg.sender);
    //     }
    //     orderManager.cancel(orderId);
    // }

    // function cancelAndWithdraw(OrderId orderId, address to) public  returns (uint256) {
    //     Order memory order = orderManager.orders(orderId);
    //     cancel(orderId);
    //     Instrument memory instrument = contango.instrument(order.positionId.getSymbol());
    //     IERC20 cashflowToken = order.cashflowCcy.isBase() ? instrument.base : instrument.quote;
    //     return withdraw(cashflowToken, order.cashflow.toUint256(), to);
    // }

    // function cancelAndWithdrawNative(OrderId orderId, address to) public  returns (uint256) {
    //     Order memory order = orderManager.orders(orderId);
    //     cancel(orderId);
    //     Instrument memory instrument = contango.instrument(order.positionId.getSymbol());

    //     IERC20 cashflowToken = order.cashflowCcy.isBase() ? instrument.base : instrument.quote;
    //     if (nativeToken != cashflowToken) revert NotNativeToken(cashflowToken);

    //     return withdrawNative(order.cashflow.toUint256(), to);
    // }

    // function _deposit(IERC20 token, uint256 amount) internal returns (uint256) {
    //     if (msg.value > 0) {
    //         if (token == nativeToken) return depositNative();
    //         else revert NotNativeToken(token);
    //     } else {
    //         return deposit(token, amount);
    //     }
    // }

    // function _authorizeUpgrade(address) internal virtual  {
    //     if (msg.sender != timelock) revert Unauthorised(msg.sender);
    // }
}

