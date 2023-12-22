// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {MarketDataTypes} from "./MarketDataTypes.sol";
import "./PositionStruct.sol";
import "./IPositionBook.sol";
import "./IFeeRouter.sol";

interface IMarketValidFuncs {
    function validPosition(
        MarketDataTypes.UpdatePositionInputs memory _params,
        Position.Props memory _position,
        int256[] memory _fees
    ) external view;

    function validIncreaseOrder(
        MarketDataTypes.UpdateOrderInputs memory _vars,
        int256 fees
    ) external view;

    function validLev(uint256 newSize, uint256 newCollateral) external view;

    function validSize(
        uint256 _size,
        uint256 _sizeDelta,
        bool _isIncrease
    ) external view;

    function validSlippagePrice(
        MarketDataTypes.UpdatePositionInputs memory _inputs
    ) external view;

    function validDecreaseOrder(
        uint256 _collateral,
        uint256 _collateralDelta,
        uint256 _size,
        uint256 _sizeDelta,
        int256 fees,
        uint256 decrOrderCount
    ) external view;


    function validMarkPrice(
        bool _isLong,
        uint256 _price,
        bool _isIncrease,
        bool _isExec,
        uint256 markPrice
    ) external view;

    function setConf(
        uint256 _minSlippage,
        uint256 _maxSlippage,
        uint256 _minLeverage,
        uint256 _maxLeverage,
        uint256 _maxTradeAmount,
        uint256 _minPay,
        uint256 _minCollateral,
        bool _allowOpen,
        bool _allowClose,
        uint256 _tokenDigits
    ) external;

    function setConfData(uint256 _data) external;

    function validCollateralDelta(
        uint256 busType,
        uint256 _collateral,
        uint256 _collateralDelta,
        uint256 _size,
        uint256 _sizeDelta,
        int256 _fees
    ) external view;

    function validateLiquidation(
        int256 pnl, // 获取仓位的盈利状态, 盈利大小
        int256 fees, // 不含清算费,包含资金费+交易手续费+执行费
        int256 liquidateFee,
        int256 collateral,
        uint256 size,
        bool _raise
    ) external view returns (uint8);

    function validPay(uint256 _pay) external view;

    function isLiquidate(
        address _account,
        address _market,
        bool _isLong,
        IPositionBook positionBook,
        IFeeRouter feeRouter,
        uint256 markPrice
    ) external view returns (uint256 _state);

    function getDecreaseOrderValidation(
        uint256 decrOrderCount
    ) external view returns (bool isValid);
}

interface IMarketValid is IMarketValidFuncs {
    struct Props {
        // minSlippage; //0-11  // 16^3   
        // maxSlippage; //12-23 // 16^3
        // minLeverage; //24-35  // 1 2^16
        // maxLeverage; //36-47 // 2000 2^16
        // minPay; // 48-59 // 10 2^8
        // minCollateral; // 60-71 // 2^8
        // maxTradeAmount = 100001;// 64-95 // 2^32
        uint256 data;
    }

    function conf() external view returns (IMarketValid.Props memory);
}

