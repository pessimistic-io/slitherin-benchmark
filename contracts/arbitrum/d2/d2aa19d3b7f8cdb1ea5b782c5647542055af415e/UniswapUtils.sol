// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import {IUniswapUtils} from "./IUniswapUtils.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";
import {TickMath} from "./TickMath.sol";
import {OracleLibrary} from "./OracleLibrary.sol";
import {PositionValue, INonfungiblePositionManager} from "./PositionValue.sol";

contract UniswapUtils is IUniswapUtils {
    function getAmountsForLiquidity(uint160 sqrtRatioX96, int24 _tickLower, int24 _tickUpper, uint128 _liquidity)
        external
        pure
        override
        returns (uint256 amount0, uint256 amount1)
    {
        return LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96, TickMath.getSqrtRatioAtTick(_tickLower), TickMath.getSqrtRatioAtTick(_tickUpper), _liquidity
        );
    }

    function fees(INonfungiblePositionManager positionManager, uint256 tokenId)
        external
        view
        override
        returns (uint256 amount0, uint256 amount1)
    {
        return PositionValue.fees(positionManager, tokenId);
    }

    function getOldestObservationSecondsAgo(address pool) external view override returns (uint32 secondsAgo) {
        return OracleLibrary.getOldestObservationSecondsAgo(pool);
    }

    function consult(address pool, uint32 secondsAgo)
        external
        view
        override
        returns (int24 arithmeticMeanTick, uint128 harmonicMeanLiquidity)
    {
        return OracleLibrary.consult(pool, secondsAgo);
    }

    function getQuoteAtTick(int24 tick, uint128 baseAmount, address baseToken, address quoteToken)
        external
        pure
        override
        returns (uint256 quoteAmount)
    {
        return OracleLibrary.getQuoteAtTick(tick, baseAmount, baseToken, quoteToken);
    }
}

