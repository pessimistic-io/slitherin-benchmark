// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import {Position, OrderInfo, OrderType} from "./Structs.sol";

interface IVaultUtilsV2 {
    function validateConfirmDelay(
        bytes32 _key,
        bool _raise
    ) external view returns (bool);

    function validateDecreasePosition(
        bool _raise, 
        uint256 _indexPrice,
        Position memory _position
    ) external view returns (bool);

    function validateLiquidation(
        bytes32 _key,
        bool _raise,
        bool _isApplyTradingFee,
        bool _isApplyBorrowFee,
        bool _isApplyFundingFee,
        uint256 _indexPrice
    ) external view returns (uint256, uint256);

    function validateLiquidation(
        bool _raise,
        bool _isApplyTradingFee,
        bool _isApplyBorrowFee,
        bool _isApplyFundingFee,
        uint256 _indexPrice,
        Position memory _position
    ) external view returns (uint256, uint256);

    function validatePositionData(
        bool _isLong,
        address _indexToken,
        OrderType _orderType,
        uint256 _latestTokenPrice,
        uint256[] memory _params,
        bool _raise,
        bool _isLatestPrice
    ) external view returns (bool);

    function validateSizeCollateralAmount(uint256 _size, uint256 _collateral) external view;

    function validateTrailingStopInputData(
        bytes32 _key,
        bool _isLong,
        uint256[] memory _params,
        uint256 _indexPrice
    ) external view returns (bool);

    function validateTrailingStopPrice(
        bool _isLong,
        bytes32 _key,
        bool _raise,
        uint256 _indexPrice
    ) external view returns (bool);

    function validateTrigger(
        bool _isLong,
        uint256 _indexPrice,
        OrderInfo memory _order
    ) external pure returns (uint8);

    function validateTrigger(
        bytes32 _key,
        uint256 _indexPrice
    ) external view returns (uint8);

    function validateAddOrRemoveCollateral(
        bytes32 _key,
        uint256 _amountIn,
        bool _isPlus,
        address _collateralToken,
        uint256 _indexPrice,
        uint256 _collateralPrice
    ) external returns (uint256, Position memory);

    function validateAddOrRemoveCollateral(
        uint256 _amountIn,
        bool _isPlus,
        address _collateralToken,
        uint256 _indexPrice,
        uint256 _collateralPrice,
        Position memory _position
    ) external returns (uint256, Position memory);

    function beforeDecreasePositionV2(
        bytes32 _key,
        uint256 _sizeDelta,
        uint256 _indexPrice
    ) external view returns (bool, int256, uint256[4] memory, Position memory);

    function beforeDecreasePosition(
        uint256 _sizeDelta,
        uint256 _indexPrice,
        Position memory _position
    ) external view returns (bool, int256, bytes memory);

    function calculatePnl(
        bytes32 _key,
        uint256 _sizeDelta,
        uint256 _loanDelta,
        uint256 _indexPrice,
        bool _isApplyTradingFee,
        bool _isApplyBorrowFee,
        bool _isApplyFundingFee,
        bool _isLiquidated
    ) external view returns (bool, uint256, uint256, int256);

    function calculatePnl(
        uint256 _sizeDelta,
        uint256 _loanDelta,
        uint256 _indexPrice,
        bool _isApplyTradingFee,
        bool _isApplyBorrowFee,
        bool _isApplyFundingFee,
        bool _isLiquidated,
        Position memory _position
    ) external view returns (bool, uint256, uint256, int256);

    function reCalculatePosition(
        uint256 _sizeDelta,
        uint256 _loanDelta,
        uint256 _indexPrice, 
        Position memory _position
    ) external view returns (uint256, int256);

    function increasePosition(
        address _collateralToken,
        uint256 _amountIn,
        uint256 _sizeDelta,
        uint256 _indexPrice,
        Position memory _position
    ) external returns (uint256, Position memory);

   function decreasePosition(
        uint256 _sizeDelta,
        address _collateralToken,
        uint256 _indexPrice,
        Position memory _position
    ) external returns (bytes memory);
}
