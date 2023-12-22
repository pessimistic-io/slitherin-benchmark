// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "./SafeERC20.sol";
import "./FullMath.sol";
import "./ConcentratedLiquidityLibrary.sol";
import "./PricesLibrary.sol";
import "./SafeAssetConverter.sol";
import "./BaseHedgedConcentratedLiquidityStrategy.sol";
import {TickMath} from "./TickMath.sol";

abstract contract BaseDynamicallyHedgedConcentratedLiquidityStrategy is BaseHedgedConcentratedLiquidityStrategy {
    using SafeAssetConverter for IAssetConverter;
    using PricesLibrary for ChainlinkPriceFeedAggregator;

    event Rehedged(int24 tick);

    int24 public rehedgeStep;

    constructor(int24 _rehedgeStep) {
        rehedgeStep = _rehedgeStep;
    }

    int24 public lastRehedgeTick;

    function _needRehedge(int24 tick) private view returns (bool) {
        return (tick > (lastRehedgeTick + int24(rehedgeStep))) || (tick < (lastRehedgeTick - int24(rehedgeStep)));
    }

    function rehedge() public checkDeviation {
        (int24 oracleTick,) = getPoolStateFromOracle();
        (int24 poolTick,) = getPoolData();

        require(_needRehedge(poolTick) && _needRehedge(oracleTick));

        uint256 currentDebt = _getCurrentDebt();
        (uint160 sqrtPriceAX96, uint160 sqrtPriceX96, uint160 sqrtPriceBX96) = _getSqrtPrices();
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, getPositionData().liquidity
        );
        uint256 borrowTokenAmount = (address(tokenToBorrow) == token0()) ? amount0 : amount1;

        if (borrowTokenAmount > currentDebt) {
            uint256 amountToBorrow = borrowTokenAmount - currentDebt;
            _borrow(amountToBorrow);
            uint256 amountToSupply =
                assetConverter.safeSwap(address(tokenToBorrow), address(collateral), amountToBorrow);
            _supply(amountToSupply);
        } else if (borrowTokenAmount < currentDebt) {
            uint256 amountToRepay = currentDebt - borrowTokenAmount;
            uint256 amountToWithdraw = pricesOracle.convert(address(tokenToBorrow), address(collateral), amountToRepay);
            _withdraw(amountToWithdraw);
            amountToRepay = assetConverter.safeSwap(address(collateral), address(tokenToBorrow), amountToWithdraw);
            _repay(amountToRepay);
        }

        emit Rehedged(poolTick);

        lastRehedgeTick = poolTick;
    }

    function _mintNewPosition(uint256 amount0, uint256 amount1) internal virtual override {
        super._mintNewPosition(amount0, amount1);
        (lastRehedgeTick,) = getPoolData();
    }
}

