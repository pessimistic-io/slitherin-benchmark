// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

import "./IPriorityPool.sol";
import "./IProtectionPool.sol";
import "./IPriorityPoolFactory.sol";
import "./ICoverRightToken.sol";
import "./ICoverRightTokenFactory.sol";
import "./IPayoutPool.sol";
import "./IWeightedFarmingPool.sol";
import "./ITreasury.sol";
import "./IExchange.sol";
import "./IERC20Decimals.sol";

abstract contract PolicyCenterDependencies {
    // Max cover length
    // Different priority pools have different max lengths
    // This max length is the maximum of all pools
    // There will also be a check in each pool
    uint256 internal constant MAX_COVER_LENGTH = 3;

    // 10000 = 100%
    // Priority pool 45%
    uint256 internal constant PREMIUM_TO_PRIORITY = 4500;
    // Protection pool 50%
    uint256 internal constant PREMIUM_TO_PROTECTION = 5000;
    // Treasury 5%
    uint256 internal constant PREMIUM_TO_TREASURY = 500;

    // Swap slippage
    // TODO: Slippage tolerance parameter 10000 as 100%
    uint256 internal constant SLIPPAGE = 100;

    address public protectionPool;
    address public priceGetter;
    address public priorityPoolFactory;
    address public coverRightTokenFactory;
    address public weightedFarmingPool;
    address public exchange;
    address public payoutPool;
    address public treasury;

    address public dexPriceGetter;
}

