// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TradingLibrary.sol";

interface ITradingExtension {

    error LimitNotMet();
    error LimitNotSet();
    error IsLimit();
    error GasTooHigh();
    error BadConstructor();

    function getVerifiedPrice(
        uint256 _asset,
        PriceData calldata _priceData,
        bytes calldata _signature,
        uint256 _withSpreadIsLong
    ) external returns(uint256 _price, uint256 _spread);

    function getRef(
        address _trader
    ) external view returns(address, uint);

    function setReferral(
        address _referrer,
        address _trader
    ) external;

    function addRefFees(
        address _trader,
        address _tigAsset,
        uint _fees
    ) external;

    function validateTrade(uint256 _asset, address _tigAsset, uint256 _margin, uint256 _leverage, uint256 _orderType) external view;

    function minPos(address) external view returns(uint);

    function modifyLongOi(
        uint256 _asset,
        address _tigAsset,
        bool _onOpen,
        uint256 _size
    ) external;

    function modifyShortOi(
        uint256 _asset,
        address _tigAsset,
        bool _onOpen,
        uint256 _size
    ) external;

    function paused() external view returns(bool);

    function _limitClose(
        uint256 _id,
        bool _tp,
        PriceData calldata _priceData,
        bytes calldata _signature
    ) external returns(uint256 _limitPrice, address _tigAsset);

    function _checkGas() external view;

    function _closePosition(
        uint256 _id,
        uint256 _price,
        uint256 _percent
    ) external returns (IPosition.Trade memory _trade, uint256 _positionSize, int256 _payout);
}
