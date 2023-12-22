// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Orders} from "./Orders.sol";

interface IStrategy {
    function fee() external view returns (uint256);

    function canExecuteTakerAsk(Orders.TakerOrder calldata takerAsk, Orders.MakerOrder calldata makerBid)
        external
        view
        returns (
            bool,
            uint256,
            uint256
        );

    function canExecuteTakerBid(Orders.TakerOrder calldata takerBid, Orders.MakerOrder calldata makerAsk)
        external
        view
        returns (
            bool,
            uint256,
            uint256
        );
}

