// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {JonesLPBearStrategy, I1inchAggregationRouterV4, ISsovV3, IERC20} from "./JonesLPBearStrategy.sol";

contract JonesDpxEthBearStrategy is JonesLPBearStrategy {
    constructor(
        address _oneInchRouter,
        address _ethSsovPV3,
        address _dpxSsovPV3,
        address _weth,
        address _dpx,
        address _owner,
        address _manager,
        address _keeperBot
    )
        JonesLPBearStrategy(
            "JonesDpxEthBearStrategy",
            I1inchAggregationRouterV4(payable(_oneInchRouter)), // 1Inch router
            ISsovV3(_ethSsovPV3), // Primary weekly Ssov-p ETH
            ISsovV3(_dpxSsovPV3), // Primary weekly Ssov-p DPX
            IERC20(_weth), // WETH
            IERC20(_dpx), // DPX
            _owner, // Governor: Jones Multisig
            _manager, // Strats: Jones Multisig
            _keeperBot // Bot
        )
    {}
}

