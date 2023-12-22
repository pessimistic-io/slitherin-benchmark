//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IMoneyMarket.sol";

interface IUnderlyingPositionFactoryEvents {
    event UnderlyingPositionCreated(address indexed account, PositionId indexed positionId);
    event MoneyMarketRegistered(MoneyMarket indexed mm, IMoneyMarket indexed moneyMarket);
}

interface IUnderlyingPositionFactory is IUnderlyingPositionFactoryEvents {
    function registerMoneyMarket(IMoneyMarket imm) external;

    function createUnderlyingPosition(PositionId) external returns (IMoneyMarket);

    function moneyMarket(MoneyMarket) external view returns (IMoneyMarket);

    function moneyMarket(PositionId) external view returns (IMoneyMarket);
}

