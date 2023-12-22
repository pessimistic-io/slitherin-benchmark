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
        uint8 _withSpreadIsLong
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

    function paused() external view returns(bool);

    function _limitClose(
        uint256 _id,
        bool _tp,
        PriceData calldata _priceData
    ) external returns(uint256 _limitPrice, address _tigAsset);
}
