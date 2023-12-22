// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IStrategy} from "./IStrategy.sol";
import {Orders} from "./Orders.sol";


contract StrategyMatchTokenId is IStrategy {
    uint256 public immutable fee;

    constructor(uint256 _fee) {
        fee = _fee;
    }

    function canExecuteTakerAsk(Orders.TakerOrder calldata takerAsk, Orders.MakerOrder calldata makerBid)
        external
        view
        override
        returns (bool, uint256, uint256)
    {
        return (
            ((makerBid.price == takerAsk.price) &&
                (makerBid.tokenId == takerAsk.tokenId) &&
                (makerBid.startTime <= block.timestamp) &&
                (makerBid.endTime >= block.timestamp)),
            makerBid.tokenId,
            makerBid.amount
        );
    }

    function canExecuteTakerBid(Orders.TakerOrder calldata takerBid, Orders.MakerOrder calldata makerAsk)
        external
        view
        override
        returns (bool, uint256, uint256)
    {
        return (
            ((makerAsk.price == takerBid.price) &&
                (makerAsk.tokenId == takerBid.tokenId) &&
                (makerAsk.startTime <= block.timestamp) &&
                (makerAsk.endTime >= block.timestamp)),
            makerAsk.tokenId,
            makerAsk.amount
        );
    }
}

