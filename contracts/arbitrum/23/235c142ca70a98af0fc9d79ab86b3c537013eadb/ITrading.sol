// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TradingLibrary.sol";

interface ITrading {

    struct TradeInfo {
        uint256 margin;
        address marginAsset;
        address stableVault;
        uint256 leverage;
        uint256 asset;
        bool direction;
        uint256 tpPrice;
        uint256 slPrice;
        address referrer;
    }
    struct ERC20PermitData {
        uint256 deadline;
        uint256 amount;
        uint8 v;
        bytes32 r;
        bytes32 s;
        bool usePermit;
    }
    struct Fees {
        uint256 daoFees;
        uint256 burnFees;
        uint256 refDiscount;
        uint256 botFees;
        uint256 keeperFees;
    }
    struct Delay {
        uint256 delay; // Block timestamp where delay ends
        bool actionType; // True for open, False for close
    }
    struct PendingMarketOrderData {
        uint256 id;
        uint256 timestamp;
        TradeInfo tradeInfo;
        address tigAsset;
        uint256 marginAfterFees;
        address trader;
    }
    struct PendingAddToPositionOrderData {
        uint256 id;
        uint256 tradeId;
        uint256 asset;
        uint256 timestamp;
        uint256 marginToAdd;
        address tigAsset;
        address trader;
    }

    error LimitNotSet();
    error OnlyEOA();
    error NotLiquidatable();
    error TradingPaused();
    error OldPriceData();
    error OrderNotFound();
    error TooEarlyToCancel();
    error BadDeposit();
    error BadWithdraw();
    error BadStopLoss();
    error IsLimit();
    error ValueNotEqualToMargin();
    error BadLeverage();
    error NotMargin();
    error NotAllowedInVault();
    error NotVault();
    error NotOwner();
    error NotAllowedPair();
    error WaitDelay();
    error NotProxy();
    error BelowMinPositionSize();
    error BadClosePercent();
    error NoPrice();
    error LiqThreshold();
    error CloseToMaxPnL();
    error BadSetter();
    error BadConstructor();
    error NotLimit();
    error LimitNotMet();

    function createMarketOrder(
        TradeInfo calldata _tradeInfo,
        PriceData calldata _priceData,
        ERC20PermitData calldata _permitData,
        address _trader
    ) external;

    function confirmMarketOrder(
        uint256 _orderId,
        PriceData calldata _priceData,
        bool _earnKeeperFee
    ) external;

    function initiateCloseOrder(
        uint256 _id,
        uint256 _percent,
        PriceData calldata _priceData,
        address _stableVault,
        address _outputToken,
        address _trader
    ) external;

    function addMargin(
        uint256 _id,
        address _stableVault,
        address _marginAsset,
        uint256 _addMargin,
        PriceData calldata _priceData,
        ERC20PermitData calldata _permitData,
        address _trader
    ) external;

    function removeMargin(
        uint256 _id,
        address _stableVault,
        address _outputToken,
        uint256 _removeMargin,
        PriceData calldata _priceData,
        address _trader
    ) external;

    function createAddToPositionOrder(
        uint256 _id,
        PriceData calldata _priceData,
        address _stableVault,
        address _marginAsset,
        uint256 _addMargin,
        ERC20PermitData calldata _permitData,
        address _trader
    ) external;

    function confirmAddToPositionOrder(
        uint256 _orderId,
        PriceData calldata _priceData,
        bool _earnKeeperFee
    ) external;

    function initiateLimitOrder(
        TradeInfo calldata _tradeInfo,
        uint256 _orderType, // 1 limit, 2 momentum
        uint256 _price,
        ERC20PermitData calldata _permitData,
        address _trader
    ) external;

    function cancelLimitOrder(
        uint256 _id,
        address _trader
    ) external;

    function updateTpSl(
        bool _type, // true is TP
        uint256 _id,
        uint256 _limitPrice,
        PriceData calldata _priceData,
        address _trader
    ) external;

    function executeLimitOrder(
        uint256 _id, 
        PriceData calldata _priceData
    ) external;

    function liquidatePosition(
        uint256 _id,
        PriceData calldata _priceData
    ) external;

    function limitClose(
        uint256 _id,
        bool _tp,
        PriceData calldata _priceData
    ) external;
}
