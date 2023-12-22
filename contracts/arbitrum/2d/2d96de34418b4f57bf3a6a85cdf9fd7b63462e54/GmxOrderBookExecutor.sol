// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { IExecutor, ExecutorIntegration, ExecutorAction } from "./IExecutor.sol";
import { Registry } from "./Registry.sol";
import { VaultBaseExternal } from "./VaultBaseExternal.sol";

import { IGmxOrderBook } from "./IGmxOrderBook.sol";

import { Constants } from "./Constants.sol";

import { GMXDecreaseOrdersStoredData } from "./GMXDecreaseOrdersStoredData.sol";

// This allows the manager to interact with the GMX order book.
// It only allows managers to open trigger orders for existing positions
// AKA DecreaseOrders AKA Take Profit and Stop Loss orders.
// Trigger orders that open a position AKA IncreaseOrders are not allowed. There is no callback from the GmxOrderBook
contract GmxOrderBookExecutor is IExecutor {
    bool public constant override requiresCPIT = false;

    event GmxCreateDecreaseOrder(
        address _indexToken,
        uint256 _sizeDelta,
        address _collateralToken,
        uint256 _collateralDelta,
        bool _isLong,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    );
    event GmxUpdateDecreaseOrder(
        uint256 _orderIndex,
        address _indexToken,
        uint256 _sizeDelta,
        address _collateralToken,
        uint256 _collateralDelta,
        bool _isLong,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    );
    event GmxCancelDecreaseOrder(
        uint256 _orderIndex,
        address _indexToken,
        address _collateralToken,
        bool _isLong
    );

    function createDecreaseOrder(
        address _indexToken,
        uint256 _sizeDelta,
        address _collateralToken,
        uint256 _collateralDelta,
        bool _isLong,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    ) external payable {
        Registry registry = VaultBaseExternal(payable(address(this)))
            .registry();
        IGmxOrderBook orderBook = registry.gmxConfig().orderBook();
        // gmx contract requires that execution fee be strictly greater than instead of gte
        uint256 minExecutionFee = orderBook.minExecutionFee() + 1;
        require(
            address(this).balance >= minExecutionFee,
            'GmxOrderBookExecutor: insufficient execution fee'
        );

        GMXDecreaseOrdersStoredData.removeExecutedOrders();
        orderBook.createDecreaseOrder{ value: minExecutionFee }(
            _indexToken,
            _sizeDelta,
            _collateralToken,
            _collateralDelta,
            _isLong,
            _triggerPrice,
            _triggerAboveThreshold
        );

        // We need to store the order index so that we can adjust it later during withdraw processing
        GMXDecreaseOrdersStoredData.pushOrderIndex(
            // decreaseOrdersIndex is incremented after
            // the order is added to the mapping. We need to subtract 1
            // to get the orderIndex for the most recently submitted order
            orderBook.decreaseOrdersIndex(address(this)) - 1,
            registry.gmxConfig().maxOpenDecreaseOrders()
        );

        emit GmxCreateDecreaseOrder(
            _indexToken,
            _sizeDelta,
            _collateralToken,
            _collateralDelta,
            _isLong,
            _triggerPrice,
            _triggerAboveThreshold
        );
        registry.emitEvent();
    }

    function updateDecreaseOrder(
        uint256 _orderIndex,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    ) external {
        Registry registry = VaultBaseExternal(payable(address(this)))
            .registry();
        IGmxOrderBook orderBook = registry.gmxConfig().orderBook();
        orderBook.updateDecreaseOrder(
            _orderIndex,
            _collateralDelta,
            _sizeDelta,
            _triggerPrice,
            _triggerAboveThreshold
        );

        (
            address collateralToken,
            ,
            address indexToken,
            ,
            bool isLong,
            ,
            ,

        ) = orderBook.getDecreaseOrder(address(this), _orderIndex);

        emit GmxUpdateDecreaseOrder(
            _orderIndex,
            indexToken,
            _sizeDelta,
            collateralToken,
            _collateralDelta,
            isLong,
            _triggerPrice,
            _triggerAboveThreshold
        );
        registry.emitEvent();
    }

    function cancelDecreaseOrder(uint256 _orderIndex) external {
        Registry registry = VaultBaseExternal(payable(address(this)))
            .registry();
        IGmxOrderBook orderBook = registry.gmxConfig().orderBook();

        (
            address collateralToken,
            ,
            address indexToken,
            ,
            bool isLong,
            ,
            ,
            uint256 executionFee
        ) = orderBook.getDecreaseOrder(address(this), _orderIndex);
        orderBook.cancelDecreaseOrder(_orderIndex);
        GMXDecreaseOrdersStoredData.removeByOrderIndex(_orderIndex);

        (bool success, ) = (
            payable(VaultBaseExternal(payable(address(this))).manager())
        ).call{ value: executionFee }('');
        // We don't care about outcome
        // Appeaze solidity compiler
        success;

        emit GmxCancelDecreaseOrder(
            _orderIndex,
            indexToken,
            collateralToken,
            isLong
        );
        registry.emitEvent();
    }

    function getStoredDecreaseOrders(
        address vault
    )
        external
        view
        returns (GMXDecreaseOrdersStoredData.GMXDecreaseOrderData[] memory)
    {
        return GMXDecreaseOrdersStoredData.getStoredDecreaseOrders(vault);
    }
}

