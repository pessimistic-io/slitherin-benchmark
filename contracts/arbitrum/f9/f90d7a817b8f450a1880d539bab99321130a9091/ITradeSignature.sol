// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./ITradeManager.sol";

interface ITradeSignature {
    function hash(OpenPositionOrder calldata openPositionOrder) external view returns (bytes32);

    function hash(ClosePositionOrder calldata closePositionOrder) external view returns (bytes32);

    function hash(ClosePositionParams calldata closePositionParams) external view returns (bytes32);

    function hashPartiallyClosePositionOrder(PartiallyClosePositionOrder calldata partiallyClosePositionOrder)
        external
        view
        returns (bytes32);

    function hashPartiallyClosePositionParams(PartiallyClosePositionParams calldata partiallyClosePositionParams)
        external
        view
        returns (bytes32);

    function hashExtendPositionOrder(ExtendPositionOrder calldata extendPositionOrder)
        external
        view
        returns (bytes32);

    function hashExtendPositionParams(ExtendPositionParams calldata extendPositionParams)
        external
        view
        returns (bytes32);

    function hashExtendPositionToLeverageOrder(ExtendPositionToLeverageOrder calldata extendPositionToLeverageOrder)
        external
        view
        returns (bytes32);

    function hashExtendPositionToLeverageParams(ExtendPositionToLeverageParams calldata extendPositionToLeverageParams)
        external
        view
        returns (bytes32);

    function hashAddMarginToPositionOrder(AddMarginToPositionOrder calldata addMarginToPositionOrder)
        external
        view
        returns (bytes32);

    function hashAddMarginToPositionParams(AddMarginToPositionParams calldata addMarginToPositionParams)
        external
        view
        returns (bytes32);

    function hashRemoveMarginFromPositionOrder(RemoveMarginFromPositionOrder calldata removeMarginFromPositionOrder)
        external
        view
        returns (bytes32);

    function hashRemoveMarginFromPositionParams(RemoveMarginFromPositionParams calldata removeMarginFromPositionParams)
        external
        view
        returns (bytes32);
}

