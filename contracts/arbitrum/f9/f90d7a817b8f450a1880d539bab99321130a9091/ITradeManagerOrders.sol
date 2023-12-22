// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./ITradeManager.sol";
import "./ITradeSignature.sol";

interface ITradeManagerOrders is ITradeManager, ITradeSignature {
    /* ========== EVENTS ========== */

    event OpenedPositionViaSignature(address indexed tradePair, uint256 indexed id, bytes indexed signature);

    event ClosedPositionViaSignature(address indexed tradePair, uint256 indexed id, bytes indexed signature);

    event PartiallyClosedPositionViaSignature(address indexed tradePair, uint256 indexed id, bytes indexed signature);

    event ExtendedPositionViaSignature(address indexed tradePair, uint256 indexed id, bytes indexed signature);

    event ExtendedPositionToLeverageViaSignature(
        address indexed tradePair, uint256 indexed id, bytes indexed signature
    );

    event AddedMarginToPositionViaSignature(address indexed tradePair, uint256 indexed id, bytes indexed signature);

    event RemovedMarginFromPositionViaSignature(address indexed tradePair, uint256 indexed id, bytes indexed signature);

    event OrderRewardTransfered(
        address indexed collateral, address indexed from, address indexed to, uint256 orderReward
    );

    /* ========== CORE FUNCTIONS - POSITIONS ========== */

    function openPositionViaSignature(
        OpenPositionOrder calldata order_,
        UpdateData[] calldata updateData_,
        address maker_,
        bytes calldata signature_
    ) external returns (uint256 positionId);

    function closePositionViaSignature(
        ClosePositionOrder calldata order_,
        UpdateData[] calldata updateData_,
        address maker_,
        bytes calldata signature_
    ) external;

    function partiallyClosePositionViaSignature(
        PartiallyClosePositionOrder calldata order_,
        UpdateData[] calldata updateData_,
        address maker_,
        bytes calldata signature_
    ) external;

    function removeMarginFromPositionViaSignature(
        RemoveMarginFromPositionOrder calldata order_,
        UpdateData[] calldata updateData_,
        address maker_,
        bytes calldata signature_
    ) external;

    function addMarginToPositionViaSignature(
        AddMarginToPositionOrder calldata order_,
        UpdateData[] calldata updateData_,
        address maker_,
        bytes calldata signature_
    ) external;

    function extendPositionViaSignature(
        ExtendPositionOrder calldata order_,
        UpdateData[] calldata updateData_,
        address maker_,
        bytes calldata signature_
    ) external;

    function extendPositionToLeverageViaSignature(
        ExtendPositionToLeverageOrder calldata order_,
        UpdateData[] calldata updateData_,
        address maker_,
        bytes calldata signature_
    ) external;
}

