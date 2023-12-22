// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Registry } from "./Registry.sol";
import { VaultBaseExternal } from "./VaultBaseExternal.sol";
import { IntegrationDataTracker, Integration } from "./IntegrationDataTracker.sol";

import { GmxHelpers } from "./GmxHelpers.sol";
import { Constants } from "./Constants.sol";
import { IGmxOrderBook } from "./IGmxOrderBook.sol";

import { GmxStoredData } from "./GmxStoredData.sol";

library GMXDecreaseOrdersStoredData {
    struct GMXDecreaseOrderData {
        uint orderIndex;
    }

    struct GmxDecreaseOrder {
        address collateralToken;
        uint256 collateralDelta;
        address indexToken;
        uint256 sizeDelta;
        bool isLong;
        uint256 triggerPrice;
        bool triggerAboveThreshold;
        uint256 executionFee;
    }

    Integration constant INTEGRATION_KEY = Integration.GMXDecreaseOrders;

    /// @notice Pushes a GMXDecreaseOrderData to storage
    /// @dev can only be called by the vault
    function pushOrderIndex(uint orderIndex, uint maxRequest) internal {
        Registry registry = VaultBaseExternal(payable(address(this)))
            .registry();
        IntegrationDataTracker dataTracker = registry.integrationDataTracker();
        require(
            address(dataTracker) != address(0),
            'no dataTracker configured'
        );

        require(
            dataTracker.getDataCount(INTEGRATION_KEY, address(this)) <
                maxRequest,
            'GMXDecreaseOrdersStoredData: max decrease orders reached'
        );

        dataTracker.pushData(
            INTEGRATION_KEY,
            abi.encode(GMXDecreaseOrderData(orderIndex))
        );
    }

    /// @notice removes the GMXPositionData in storage for the calling vault if the GMX position is empty
    function removeExecutedOrders() internal {
        Registry registry = VaultBaseExternal(payable(address(this)))
            .registry();
        IntegrationDataTracker dataTracker = registry.integrationDataTracker();
        require(
            address(dataTracker) != address(0),
            'no dataTracker configured'
        );

        uint count = dataTracker.getDataCount(INTEGRATION_KEY, address(this));

        for (uint256 i = count; i > 0; i--) {
            GMXDecreaseOrderData memory orderData = abi.decode(
                dataTracker.getData(INTEGRATION_KEY, address(this), i - 1),
                (GMXDecreaseOrderData)
            );
            if (!isActiveOrder(address(this), orderData)) {
                dataTracker.removeData(INTEGRATION_KEY, i - 1);
            }
        }
    }

    function removeByOrderIndex(uint orderIndex) internal {
        Registry registry = VaultBaseExternal(payable(address(this)))
            .registry();
        IntegrationDataTracker dataTracker = registry.integrationDataTracker();
        require(
            address(dataTracker) != address(0),
            'no dataTracker configured'
        );

        uint count = dataTracker.getDataCount(INTEGRATION_KEY, address(this));

        for (uint256 i = count; i > 0; i--) {
            GMXDecreaseOrderData memory orderData = abi.decode(
                dataTracker.getData(INTEGRATION_KEY, address(this), i - 1),
                (GMXDecreaseOrderData)
            );
            if (orderData.orderIndex == orderIndex) {
                dataTracker.removeData(INTEGRATION_KEY, i - 1);
                break;
            }
        }
    }

    /// @notice adjusts the matching orders based on the withdraw portion
    function adjustMatchingOrders(
        GmxStoredData.GMXPositionData memory gmxPositionData,
        uint portionBeingWithdraw,
        uint postWithdrawPostionSize,
        uint postWithdrawCollateral,
        address payable manager
    ) internal {
        Registry registry = VaultBaseExternal(payable(address(this)))
            .registry();
        IntegrationDataTracker dataTracker = registry.integrationDataTracker();
        require(
            address(dataTracker) != address(0),
            'no dataTracker configured'
        );

        uint count = dataTracker.getDataCount(INTEGRATION_KEY, address(this));

        for (uint256 i = count; i > 0; i--) {
            GMXDecreaseOrderData memory orderData = abi.decode(
                dataTracker.getData(INTEGRATION_KEY, address(this), i - 1),
                (GMXDecreaseOrderData)
            );

            IGmxOrderBook orderBook = registry.gmxConfig().orderBook();

            GmxDecreaseOrder memory decreaseOrder;
            (
                decreaseOrder.collateralToken,
                decreaseOrder.collateralDelta,
                decreaseOrder.indexToken,
                decreaseOrder.sizeDelta,
                decreaseOrder.isLong,
                decreaseOrder.triggerPrice,
                decreaseOrder.triggerAboveThreshold,
                decreaseOrder.executionFee
            ) = orderBook.getDecreaseOrder(address(this), orderData.orderIndex);

            if (
                decreaseOrder.collateralToken ==
                gmxPositionData._collateralToken &&
                decreaseOrder.indexToken == gmxPositionData._indexToken &&
                decreaseOrder.isLong == gmxPositionData._isLong
            ) {
                if (postWithdrawPostionSize == 0) {
                    // The position has been closed by the withdraw
                    // Cancel the order and return the execution fee
                    dataTracker.removeData(
                        Integration.GMXDecreaseOrders,
                        i - 1
                    );
                    orderBook.cancelDecreaseOrder(orderData.orderIndex);
                    (bool success, ) = manager.call{
                        value: decreaseOrder.executionFee
                    }('');
                    // We don't care about outcome
                    // Appeaze solidity compiler
                    success;
                } else {
                    // Adjust the order based on the withdrawn portion
                    uint collateralDeltaAfterReduction = (decreaseOrder
                        .collateralDelta *
                        (Constants.PORTION_DIVISOR - portionBeingWithdraw)) /
                        Constants.PORTION_DIVISOR;

                    if (
                        collateralDeltaAfterReduction > postWithdrawCollateral
                    ) {
                        collateralDeltaAfterReduction = postWithdrawCollateral;
                    }

                    uint sizeDeltaAfterReduction = (decreaseOrder.sizeDelta *
                        (Constants.PORTION_DIVISOR - portionBeingWithdraw)) /
                        Constants.PORTION_DIVISOR;

                    if (sizeDeltaAfterReduction > postWithdrawPostionSize) {
                        sizeDeltaAfterReduction = postWithdrawPostionSize;
                    }

                    orderBook.updateDecreaseOrder(
                        orderData.orderIndex,
                        collateralDeltaAfterReduction,
                        sizeDeltaAfterReduction,
                        decreaseOrder.triggerPrice,
                        decreaseOrder.triggerAboveThreshold
                    );
                }
            }
        }
    }

    /// @notice gets all GMXPositionData in storage for the vault
    function getStoredDecreaseOrders(
        address vault
    ) internal view returns (GMXDecreaseOrderData[] memory) {
        Registry registry = VaultBaseExternal(payable(vault)).registry();
        IntegrationDataTracker dataTracker = registry.integrationDataTracker();
        require(
            address(dataTracker) != address(0),
            'no dataTracker configured'
        );

        bytes[] memory orderData = registry.integrationDataTracker().getAllData(
            INTEGRATION_KEY,
            vault
        );
        GMXDecreaseOrderData[] memory orders = new GMXDecreaseOrderData[](
            orderData.length
        );
        for (uint256 i = 0; i < orderData.length; i++) {
            orders[i] = abi.decode(orderData[i], (GMXDecreaseOrderData));
        }
        return orders;
    }

    /// @notice checks if there is an active order for the given position
    function isActiveOrder(
        address vault,
        GMXDecreaseOrderData memory orderData
    ) internal view returns (bool isActive) {
        Registry registry = VaultBaseExternal(payable(vault)).registry();
        IGmxOrderBook orderBook = registry.gmxConfig().orderBook();
        (address collateralToken, , , , , , , ) = orderBook.getDecreaseOrder(
            vault,
            orderData.orderIndex
        );

        if (collateralToken != address(0)) {
            return true;
        }
    }
}

