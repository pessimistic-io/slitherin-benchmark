// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.17;

import "./TradeManager.sol";
import "./TradeSignature.sol";
import "./ITradeManagerOrders.sol";

/**
 * @title TradeManagerOrders
 * @notice Exposes Functions to open, alter and close positions via signed orders.
 * @dev This contract is called by the Unlimited backend. This allows for an order book.
 */
contract TradeManagerOrders is ITradeManagerOrders, TradeSignature, TradeManager {
    using SafeERC20 for IERC20;

    mapping(bytes32 => TradeId) public sigHashToTradeId;

    /**
     * @notice Constructs the TradeManager contract.
     * @param controller_ The address of the controller.
     * @param userManager_ The address of the user manager.
     */
    constructor(IController controller_, IUserManager userManager_)
        TradeManager(controller_, userManager_)
        TradeSignature()
    {}

    /**
     * @notice Opens a position with a signature
     * @param order_ Order struct
     * @param maker_ address of the maker
     * @param signature_ signature of order_ by maker_
     */
    function openPositionViaSignature(
        OpenPositionOrder calldata order_,
        UpdateData[] calldata updateData_,
        address maker_,
        bytes calldata signature_
    ) external onlyOrderExecutor onlyActiveTradePair(order_.params.tradePair) returns (uint256) {
        _updateContracts(updateData_);
        _processSignature(order_, maker_, signature_);
        _verifyConstraints(
            order_.params.tradePair, order_.constraints, order_.params.isShort ? UsePrice.MIN : UsePrice.MAX
        );

        _transferOrderReward(order_.params.tradePair, maker_, msg.sender);

        uint256 positionId = _openPosition(order_.params, maker_);

        sigHashToTradeId[keccak256(signature_)] = TradeId(order_.params.tradePair, uint96(positionId));

        emit OpenedPositionViaSignature(order_.params.tradePair, positionId, signature_);

        return positionId;
    }

    /**
     * @notice Closes a position with a signature
     * @param order_ Order struct
     * @param maker_ address of the maker
     * @param signature_ signature of order_ by maker_
     */
    function closePositionViaSignature(
        ClosePositionOrder calldata order_,
        UpdateData[] calldata updateData_,
        address maker_,
        bytes calldata signature_
    ) external onlyOrderExecutor onlyActiveTradePair(order_.params.tradePair) {
        _updateContracts(updateData_);
        _processSignature(order_, maker_, signature_);

        _verifyConstraints(
            order_.params.tradePair,
            order_.constraints,
            ITradePair(order_.params.tradePair).positionIsShort(order_.params.positionId) ? UsePrice.MAX : UsePrice.MIN
        );

        _transferOrderReward(order_.params.tradePair, maker_, msg.sender);

        // make for all orders
        _closePosition(_injectPositionIdToCloseOrder(order_).params, maker_);

        emit ClosedPositionViaSignature(order_.params.tradePair, order_.params.positionId, signature_);
    }

    /**
     * @notice Partially closes a position with a signature
     * @param order_ Order struct
     * @param maker_ address of the maker
     * @param signature_ signature of order_ by maker_
     */
    function partiallyClosePositionViaSignature(
        PartiallyClosePositionOrder calldata order_,
        UpdateData[] calldata updateData_,
        address maker_,
        bytes calldata signature_
    ) external onlyOrderExecutor onlyActiveTradePair(order_.params.tradePair) {
        _updateContracts(updateData_);
        _processSignature(order_, maker_, signature_);

        // Verify Constraints
        _verifyConstraints(
            order_.params.tradePair,
            order_.constraints,
            ITradePair(order_.params.tradePair).positionIsShort(order_.params.positionId) ? UsePrice.MAX : UsePrice.MIN
        );

        _transferOrderReward(order_.params.tradePair, maker_, msg.sender);

        _partiallyClosePosition(_injectPositionIdToPartiallyCloseOrder(order_).params, maker_);

        emit PartiallyClosedPositionViaSignature(order_.params.tradePair, order_.params.positionId, signature_);
    }

    /**
     * @notice Extends a position with a signature
     * @param order_ Order struct
     * @param maker_ address of the maker
     * @param signature_ signature of order_ by maker_
     */
    function extendPositionViaSignature(
        ExtendPositionOrder calldata order_,
        UpdateData[] calldata updateData_,
        address maker_,
        bytes calldata signature_
    ) external onlyOrderExecutor onlyActiveTradePair(order_.params.tradePair) {
        _updateContracts(updateData_);
        _processSignatureExtendPosition(order_, maker_, signature_);

        // Verify Constraints
        _verifyConstraints(
            order_.params.tradePair,
            order_.constraints,
            ITradePair(order_.params.tradePair).positionIsShort(order_.params.positionId) ? UsePrice.MIN : UsePrice.MAX
        );

        _transferOrderReward(order_.params.tradePair, maker_, msg.sender);

        _extendPosition(_injectPositionIdToExtendOrder(order_).params, maker_);

        emit ExtendedPositionViaSignature(order_.params.tradePair, order_.params.positionId, signature_);
    }

    /**
     * @notice Partially extends a position to leverage with a signature
     * @param order_ Order struct
     * @param maker_ address of the maker
     * @param signature_ signature of order_ by maker_
     */
    function extendPositionToLeverageViaSignature(
        ExtendPositionToLeverageOrder calldata order_,
        UpdateData[] calldata updateData_,
        address maker_,
        bytes calldata signature_
    ) external onlyOrderExecutor onlyActiveTradePair(order_.params.tradePair) {
        _updateContracts(updateData_);
        _processSignatureExtendPositionToLeverage(order_, maker_, signature_);

        // Verify Constraints
        _verifyConstraints(
            order_.params.tradePair,
            order_.constraints,
            ITradePair(order_.params.tradePair).positionIsShort(order_.params.positionId) ? UsePrice.MIN : UsePrice.MAX
        );

        _transferOrderReward(order_.params.tradePair, maker_, msg.sender);

        _extendPositionToLeverage(_injectPositionIdToExtendToLeverageOrder(order_).params, maker_);

        emit ExtendedPositionToLeverageViaSignature(order_.params.tradePair, order_.params.positionId, signature_);
    }

    /**
     * @notice Adds margin to a position with a signature
     * @param order_ Order struct
     * @param maker_ address of the maker
     * @param signature_ signature of order_ by maker_
     */
    function addMarginToPositionViaSignature(
        AddMarginToPositionOrder calldata order_,
        UpdateData[] calldata updateData_,
        address maker_,
        bytes calldata signature_
    ) external onlyOrderExecutor onlyActiveTradePair(order_.params.tradePair) {
        _updateContracts(updateData_);
        _processSignatureAddMarginToPosition(order_, maker_, signature_);

        // Verify Constraints
        _verifyConstraints(
            order_.params.tradePair,
            order_.constraints,
            ITradePair(order_.params.tradePair).positionIsShort(order_.params.positionId) ? UsePrice.MAX : UsePrice.MIN
        );

        _transferOrderReward(order_.params.tradePair, maker_, msg.sender);

        _addMarginToPosition(_injectPositionIdToAddMarginOrder(order_).params, maker_);

        emit AddedMarginToPositionViaSignature(order_.params.tradePair, order_.params.positionId, signature_);
    }

    /**
     * @notice Removes margin from a position with a signature
     * @param order_ Order struct
     * @param maker_ address of the maker
     * @param signature_ signature of order_ by maker_
     */
    function removeMarginFromPositionViaSignature(
        RemoveMarginFromPositionOrder calldata order_,
        UpdateData[] calldata updateData_,
        address maker_,
        bytes calldata signature_
    ) external onlyOrderExecutor onlyActiveTradePair(order_.params.tradePair) {
        _updateContracts(updateData_);
        _processSignatureRemoveMarginFromPosition(order_, maker_, signature_);

        // Verify Constraints
        _verifyConstraints(
            order_.params.tradePair,
            order_.constraints,
            ITradePair(order_.params.tradePair).positionIsShort(order_.params.positionId) ? UsePrice.MAX : UsePrice.MIN
        );

        _transferOrderReward(order_.params.tradePair, maker_, msg.sender);

        _removeMarginFromPosition(_injectPositionIdToRemoveMarginOrder(order_).params, maker_);

        emit RemovedMarginFromPositionViaSignature(order_.params.tradePair, order_.params.positionId, signature_);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @notice Maybe Injects the positionId to the order. Injects positionId when order has a signatureHash
     * @dev Retrieves the positionId from sigHashToPositionId via the order's signatureHash.
     * @param order_ Close Position Order
     * @return newOrder with positionId injected
     */
    function _injectPositionIdToCloseOrder(ClosePositionOrder calldata order_)
        internal
        view
        returns (ClosePositionOrder memory newOrder)
    {
        newOrder = order_;
        if (newOrder.params.positionId == type(uint256).max) {
            require(
                newOrder.signatureHash > 0,
                "TradeManagerOrders::_injectPositionIdToCloseOrder: Modify order requires either a position id or a signature hash"
            );

            TradeId memory tradeId = sigHashToTradeId[newOrder.signatureHash];

            require(
                tradeId.tradePair == newOrder.params.tradePair,
                "TradeManagerOrders::_injectPositionIdToCloseOrder: Wrong trade pair"
            );

            newOrder.params.positionId = tradeId.positionId;
        }
    }

    /**
     * @notice Maybe Injects the positionId to the order. Injects positionId when order has a signatureHash
     * @dev Retrieves the positionId from sigHashToPositionId via the order's signatureHash.
     * @param order_ Partially Close Position Order
     * @return newOrder with positionId injected
     */
    function _injectPositionIdToPartiallyCloseOrder(PartiallyClosePositionOrder calldata order_)
        internal
        view
        returns (PartiallyClosePositionOrder memory newOrder)
    {
        newOrder = order_;
        if (newOrder.params.positionId == type(uint256).max) {
            require(
                newOrder.signatureHash > 0,
                "TradeManagerOrders::_injectPositionIdToPartiallyCloseOrder: Modify order requires either a position id or a signature hash"
            );

            TradeId memory tradeId = sigHashToTradeId[newOrder.signatureHash];

            require(
                tradeId.tradePair == newOrder.params.tradePair,
                "TradeManagerOrders::_injectPositionIdToPartiallyCloseOrder: Wrong trade pair"
            );

            newOrder.params.positionId = tradeId.positionId;
        }
    }

    /**
     * @notice Maybe Injects the positionId to the order. Injects positionId when order has a signatureHash
     * @dev Retrieves the positionId from sigHashToPositionId via the order's signatureHash.
     * @param order_ Extend Position Order
     * @return newOrder with positionId injected
     */
    function _injectPositionIdToExtendOrder(ExtendPositionOrder calldata order_)
        internal
        view
        returns (ExtendPositionOrder memory newOrder)
    {
        newOrder = order_;
        if (newOrder.params.positionId == type(uint256).max) {
            require(
                newOrder.signatureHash > 0,
                "TradeManagerOrders::_injectPositionIdToExtendOrder: Modify order requires either a position id or a signature hash"
            );

            TradeId memory tradeId = sigHashToTradeId[newOrder.signatureHash];

            require(
                tradeId.tradePair == newOrder.params.tradePair,
                "TradeManagerOrders::_injectPositionIdToExtendOrder: Wrong trade pair"
            );

            newOrder.params.positionId = tradeId.positionId;
        }
    }

    /**
     * @notice Maybe Injects the positionId to the order. Injects positionId when order has a signatureHash
     * @dev Retrieves the positionId from sigHashToPositionId via the order's signatureHash.
     * @param order_ Extend Position To Leverage Order
     * @return newOrder with positionId injected
     */
    function _injectPositionIdToExtendToLeverageOrder(ExtendPositionToLeverageOrder calldata order_)
        internal
        view
        returns (ExtendPositionToLeverageOrder memory newOrder)
    {
        newOrder = order_;
        if (newOrder.params.positionId == type(uint256).max) {
            require(
                newOrder.signatureHash > 0,
                "TradeManagerOrders::_injectPositionIdToExtendToLeverageOrder: Modify order requires either a position id or a signature hash"
            );

            TradeId memory tradeId = sigHashToTradeId[newOrder.signatureHash];

            require(
                tradeId.tradePair == newOrder.params.tradePair,
                "TradeManagerOrders::_injectPositionIdToExtendToLeverageOrder: Wrong trade pair"
            );

            newOrder.params.positionId = tradeId.positionId;
        }
    }

    /**
     * @notice Maybe Injects the positionId to the order. Injects positionId when order has a signatureHash
     * @dev Retrieves the positionId from sigHashToPositionId via the order's signatureHash.
     * @param order_ Add Margin Order
     * @return newOrder with positionId injected
     */
    function _injectPositionIdToAddMarginOrder(AddMarginToPositionOrder calldata order_)
        internal
        view
        returns (AddMarginToPositionOrder memory newOrder)
    {
        newOrder = order_;
        if (newOrder.params.positionId == type(uint256).max) {
            require(
                newOrder.signatureHash > 0,
                "TradeManagerOrders::_injectPositionIdToAddMarginOrder: Modify order requires either a position id or a signature hash"
            );

            TradeId memory tradeId = sigHashToTradeId[newOrder.signatureHash];

            require(
                tradeId.tradePair == newOrder.params.tradePair,
                "TradeManagerOrders::_injectPositionIdToAddMarginOrder: Wrong trade pair"
            );

            newOrder.params.positionId = tradeId.positionId;
        }
    }

    /**
     * @notice Maybe Injects the positionId to the order. Injects positionId when order has a signatureHash
     * @dev Retrieves the positionId from sigHashToPositionId via the order's signatureHash.
     * @param order_ Remove Margin Order
     * @return newOrder with positionId injected
     */
    function _injectPositionIdToRemoveMarginOrder(RemoveMarginFromPositionOrder calldata order_)
        internal
        view
        returns (RemoveMarginFromPositionOrder memory newOrder)
    {
        newOrder = order_;
        if (newOrder.params.positionId == type(uint256).max) {
            require(
                newOrder.signatureHash > 0,
                "TradeManagerOrders::_injectPositionIdToRemoveMarginOrder: Modify order requires either a position id or a signature hash"
            );

            TradeId memory tradeId = sigHashToTradeId[newOrder.signatureHash];

            require(
                tradeId.tradePair == newOrder.params.tradePair,
                "TradeManagerOrders::_injectPositionIdToRemoveMarginOrder: Wrong trade pair"
            );

            newOrder.params.positionId = tradeId.positionId;
        }
    }

    /**
     * @notice transfers the order reward from maker to executor
     * @param tradePair_ address of the trade pair (collateral is read from tradePair)
     * @param from_ address of the maker
     * @param to_ address of the executor
     */
    function _transferOrderReward(address tradePair_, address from_, address to_) internal {
        IERC20 collateral = ITradePair(tradePair_).collateral();
        uint256 orderReward = controller.orderRewardOfCollateral(address(collateral));
        if (orderReward > 0) {
            collateral.safeTransferFrom(from_, to_, orderReward);
        }

        emit OrderRewardTransfered(address(collateral), from_, to_, orderReward);
    }

    /* ========== RESCTRICTION FUNCTIONS ========== */

    function _verifyOrderExecutor() internal view {
        require(
            controller.isOrderExecutor(msg.sender),
            "TradeManagerOrders::_verifyOrderExecutor: Sender is not order executor"
        );
    }

    /* =========== MODIFIER =========== */

    modifier onlyOrderExecutor() {
        _verifyOrderExecutor();
        _;
    }
}

