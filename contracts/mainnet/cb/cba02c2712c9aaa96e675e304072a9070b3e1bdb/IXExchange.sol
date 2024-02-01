// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderTypes} from "./OrderTypes.sol";

interface IXExchange {
    event CancelAllOrders(address indexed user, uint256 newNonce);
    event CancelMultipleOrders(bytes32[] orderItemHashes);
    event TransferManagerSelectorUpdated(address transferManagerSelector);
    event RoyaltyEngineUpdated(address royaltyEngine);
    event MarketplaceFeeEngineUpdated(address marketplaceFeeEngine);
    event StrategyManagerUpdated(address strategyManager);
    event CurrencyManagerUpdated(address currencyManager);
    event TakerAsk(
        address indexed taker,
        address indexed maker,
        address indexed strategy,
        bytes32 orderHash,
        uint256 itemIdx,
        bytes32 orderItemHash,
        OrderTypes.Fulfillment fulfillment
    );
    event TakerBid(
        address indexed taker,
        address indexed maker,
        address indexed strategy,
        bytes32 orderHash,
        uint256 itemIdx,
        bytes32 orderItemHash,
        OrderTypes.Fulfillment fulfillment
    );

    function matchAskWithTakerBidUsingETH(
        OrderTypes.MakerOrder calldata makerAsk,
        OrderTypes.TakerOrder calldata takerBid
    ) external payable;

    function matchAskWithTakerBid(
        OrderTypes.MakerOrder calldata makerAsk,
        OrderTypes.TakerOrder calldata takerBid
    ) external;

    function matchBidWithTakerAsk(
        OrderTypes.MakerOrder calldata makerBid,
        OrderTypes.TakerOrder calldata takerAsk
    ) external;

    function cancelAllOrdersForSender(uint256 nonce) external;

    function cancelMultipleOrders(
        OrderTypes.MakerOrder[] calldata orders,
        uint256[][] calldata itemIdxs
    ) external;
}

