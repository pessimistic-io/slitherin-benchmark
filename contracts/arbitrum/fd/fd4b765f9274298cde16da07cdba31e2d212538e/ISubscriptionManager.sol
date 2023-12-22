// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface ISubscriptionManager {
    struct SubscriptionConfig {
        address peopleFeeReceiver;
        // in loot8tokenDecimals
        uint256 floorPrice;
        // percentage in basis points in loot8decimals
        uint256 platformFeePercent;
        uint256 peopleFeePercent;
        bool tradingEnabled;
        bool subscriptionHasStarted;
        uint256[5] __gap;
    }

    event Trade(
        address _trader,
        address _passport,
        bool _isBuy,
        uint256 _passportAmount,
        uint256 _price
    );

    event SubscriptionConfigSet(
        address _passport,
        uint256 _price,
        bool _tradingEnabled,
        bool _subscriptionHasStarted
    );

    function setPassportSubscriptionConfig(
        address passport,
        uint256 _peopleFeePercent,
        uint256 _platformFeePercent,
        address _peopleFeeReceiver,
        uint256 _floorPrice,
        bool _tradingEnabled,
        bool _startSubscriptions
    ) external;

    function setTradingEnabled(address passport, bool _tradingEnabled) external;

    function getPrice(
        uint256 _floorPrice,
        uint256 supply,
        uint256 amount
    ) external returns (uint256);

    function getBuyPrice(
        address passport,
        uint256 amount
    ) external view returns (uint256, uint256, uint256);

    function getSellPrice(
        address passport,
        uint256 amount
    ) external view returns (uint256, uint256, uint256);

    function subscribe(address passport, uint256 amount) external;
    function unsubscribe(address passport, uint256[] memory _passportIds) external;
}

