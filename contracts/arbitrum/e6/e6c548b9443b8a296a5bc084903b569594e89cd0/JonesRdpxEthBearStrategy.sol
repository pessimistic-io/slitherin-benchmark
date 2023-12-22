// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {JonesLPBearStrategy, I1inchAggregationRouterV4, ISsovV3, IERC20} from "./JonesLPBearStrategy.sol";

contract JonesRdpxEthBearStrategy is JonesLPBearStrategy {
    constructor(
        address _oneInchRouter,
        address _ethSsovPV3,
        address _rdpxSsovPV3,
        address _weth,
        address _rdpx,
        address _owner,
        address _manager,
        address _keeperBot
    )
        JonesLPBearStrategy(
            "JonesRdpxEthBearStrategy",
            I1inchAggregationRouterV4(payable(_oneInchRouter)), // 1Inch router
            ISsovV3(_ethSsovPV3), // Primary weekly Ssov-p ETH
            ISsovV3(_rdpxSsovPV3), // Primary weekly Ssov RDPX
            IERC20(_weth), // WETH
            IERC20(_rdpx), // RDPX
            _owner, // Governor: Jones Multisig
            _manager, // Strats: Jones Multisig
            _keeperBot // Bot
        )
    {}
}

