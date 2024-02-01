// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./Ownable.sol";
import "./Constants.sol";

contract MarketRegistry is Ownable, Constants {
    struct TradeDetail {
        uint256 marketId;
        uint256 value;
        bytes tradeData;
    }

    struct Market {
        address proxy; //custom market proxy
        bool isLib; //是否通过委托调用的方式，调用Market市场合约。大多数情况是true，因为Market合约中会校验msg。sender是否为接单者
        bool isActive;
    }

    Market[] public markets;

    constructor(address universalMarektProxy) {
        markets.push(Market(SEAPORT, false, true)); //market_id=0,call
        markets.push(Market(universalMarektProxy, true, true)); //market_id=1,delegatecall
    }

    function addMarket(address proxy, bool isLib) external onlyOwner {
        markets.push(Market(proxy, isLib, true));
    }

    function addMarkets(address[] memory proxies, bool[] memory isLibs)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < proxies.length; i++) {
            markets.push(Market(proxies[i], isLibs[i], true));
        }
    }

    function setMarketStatus(uint256 marketId, bool newStatus)
        external
        onlyOwner
    {
        Market storage market = markets[marketId];
        market.isActive = newStatus;
    }

    function setMarketProxy(
        uint256 marketId,
        address newProxy,
        bool isLib
    ) external onlyOwner {
        Market storage market = markets[marketId];
        market.proxy = newProxy;
        market.isLib = isLib;
    }
}

