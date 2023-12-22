// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {JonesLPBullStrategy, I1inchAggregationRouterV4, ISsovV3, IERC20} from "./JonesLPBullStrategy.sol";

contract JonesDpxEthBullStrategy is JonesLPBullStrategy {
    constructor(
        address _oneInchRouter,
        address _ethSsovV3,
        address _dpxSsovV3,
        address _weth,
        address _dpx,
        address _owner,
        address _manager,
        address _keeperBot
    )
        JonesLPBullStrategy(
            "JonesDpxEthBullStrategy",
            I1inchAggregationRouterV4(payable(_oneInchRouter)), // 1Inch router
            ISsovV3(_ethSsovV3), // Primary weekly Ssov ETH
            ISsovV3(_dpxSsovV3), // Primary weekly Ssov DPX
            IERC20(_weth), // WETH
            IERC20(_dpx), // DPX
            _owner, // Governor: Jones Multisig
            _manager, // Strats: Jones Multisig
            _keeperBot // Bot
        )
    {}
}

