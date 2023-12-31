// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {ConvexVaultDeploymentParams, Curve2TokenConvexStrategyContext} from "./CurveVaultTypes.sol";
import {Curve2TokenPoolMixin} from "./Curve2TokenPoolMixin.sol";
import {NotionalProxy} from "./NotionalProxy.sol";
import {ICurve2TokenPool} from "./ICurvePool.sol";

abstract contract Curve2TokenVaultMixin is Curve2TokenPoolMixin {
    constructor(NotionalProxy notional_, ConvexVaultDeploymentParams memory params)
        Curve2TokenPoolMixin(notional_, params) { }

    function _checkReentrancyContext() internal override {
        // We need to set the LP token amount to 1 for Curve V2 pools to bypass
        // the underflow check
        uint256[2] memory minAmounts;
        ICurve2TokenPool(address(CURVE_POOL)).remove_liquidity(IS_CURVE_V2 ? 1 : 0, minAmounts);
    }

    function _strategyContext() internal view returns (Curve2TokenConvexStrategyContext memory) {
        return Curve2TokenConvexStrategyContext({
            baseStrategy: _baseStrategyContext(),
            poolContext: _twoTokenPoolContext(),
            stakingContext: _convexStakingContext()
        });
    }

    uint256[40] private __gap; // Storage gap for future potential upgrades
}

