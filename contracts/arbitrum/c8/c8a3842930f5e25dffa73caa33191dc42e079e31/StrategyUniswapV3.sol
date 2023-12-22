// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {Strategy} from "./Strategy.sol";
import {IERC20} from "./IERC20.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";
import {TickMath} from "./TickMath.sol";
import {FullMath} from "./FullMath.sol";
import {TickLib} from "./TickLib.sol";
import {BytesLib} from "./BytesLib.sol";
import {FixedPoint128} from "./FixedPoint128.sol";
import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {ISwapRouter} from "./ISwapRouter.sol";
import {IUniswapV3SwapCallback} from "./IUniswapV3SwapCallback.sol";
import {IUniswapV3MintCallback} from "./IUniswapV3MintCallback.sol";
import {IOracle} from "./IOracle.sol";

contract StrategyUniswapV3 is Strategy, IUniswapV3SwapCallback, IUniswapV3MintCallback {
    error NoLiquidity();
    error TooLittleReceived();

    string public name;
    IUniswapV3Pool public immutable pool;
    IERC20 public immutable token0;
    IERC20 public immutable token1;
    uint24 public immutable fee;
    int24 public tickScale;
    int24 public immutable tickSpacing;
    int24 public minTick;
    int24 public maxTick;
    uint160 public minSqrtRatio;
    uint160 public maxSqrtRatio;
    uint160 public immutable minSqrtRatioFixed;
    uint160 public immutable maxSqrtRatioFixed;

    constructor(
        address _strategyHelper,
        address _pool,
        int24 _tickScale
    ) Strategy(_strategyHelper) {
        pool = IUniswapV3Pool(_pool);
        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());
        fee = pool.fee();
        tickSpacing = pool.tickSpacing();
        tickScale = _tickScale;
        minTick = TickLib.nearestUsableTick(TickMath.MIN_TICK, tickSpacing);
        maxTick = TickLib.nearestUsableTick(TickMath.MAX_TICK, tickSpacing);
        minSqrtRatioFixed = TickMath.getSqrtRatioAtTick(minTick);
        maxSqrtRatioFixed = TickMath.getSqrtRatioAtTick(maxTick);
        if (_tickScale > 0) {
            (minTick, maxTick) = getTickRange(_tickScale, _pool);
        }
        minSqrtRatio = TickMath.getSqrtRatioAtTick(minTick);
        maxSqrtRatio = TickMath.getSqrtRatioAtTick(maxTick);
        name = string(abi.encodePacked("UniswapV3 ", token0.symbol(), "/", token1.symbol()));
    }

    function rate(uint256 sha) public view override returns (uint256) {
        if (sha == 0 || totalShares == 0) return 0;
        (uint160 midX96, int24 tick,,,,,) = pool.slot0();
        (
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = pool.positions(getPositionID());

        (uint256 amt0, uint256 amt1) = LiquidityAmounts.getAmountsForLiquidity(
            midX96, minSqrtRatio, maxSqrtRatio, liquidity
        );
        {
            (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = TickLib.getFeeGrowthInside(
                address(pool), minTick, maxTick, tick, pool.feeGrowthGlobal0X128(), pool.feeGrowthGlobal1X128()
            );
            uint256 newTokensOwed0 = FullMath.mulDiv(
                feeGrowthInside0X128 - feeGrowthInside0LastX128, liquidity, FixedPoint128.Q128);

            uint256 newTokensOwed1 = FullMath.mulDiv(
                feeGrowthInside1X128 - feeGrowthInside1LastX128, liquidity, FixedPoint128.Q128);
            amt0 += uint256(tokensOwed0) + newTokensOwed0;
            amt1 += uint256(tokensOwed1) + newTokensOwed1;
        }

        uint256 val0 = strategyHelper.value(address(token0), amt0);
        uint256 val1 = strategyHelper.value(address(token1), amt1);
        return sha * (val0 + val1) / totalShares;
    }

    function _mint(address ast, uint256 amt, bytes calldata dat) internal override returns (uint256) {
        uint256 slp = getSlippage(dat);
        (uint128 tma,,,,) = pool.positions(getPositionID());
        uint256 haf = amt / 2;
        IERC20(ast).approve(address(strategyHelper), amt);
        uint256 amt0 = strategyHelper.swap(ast, address(token0), haf, slp, address(this));
        uint256 amt1 = strategyHelper.swap(ast, address(token1), amt-haf, slp, address(this));
        (uint160 midX96,,,,,,) = pool.slot0();
        uint128 liq = LiquidityAmounts.getLiquidityForAmounts(
            midX96, minSqrtRatio, maxSqrtRatio, amt0, amt1
        );
        if (liq == 0) revert NoLiquidity();
        pool.mint(address(this), minTick, maxTick, liq, "");
        return tma == 0 ? liq : liq * totalShares / tma;
    }

    function _burn(address ast, uint256 amt, bytes calldata dat) internal override returns (uint256) {
        uint256 slp = getSlippage(dat);
        (uint128 tma,,,,) = pool.positions(getPositionID());
        uint128 liq = uint128(amt) * tma / uint128(totalShares);
        if (liq > 0) pool.burn(minTick, maxTick, liq);
        pool.collect(address(this), minTick, maxTick, type(uint128).max, type(uint128).max);
        uint256 bal0 = token0.balanceOf(address(this));
        uint256 bal1 = token1.balanceOf(address(this));
        token0.approve(address(strategyHelper), bal0);
        token1.approve(address(strategyHelper), bal1);
        uint256 amt0 = strategyHelper.swap(address(token0), ast, bal0, slp, msg.sender);
        uint256 amt1 = strategyHelper.swap(address(token1), ast, bal1, slp, msg.sender);
        return amt0 + amt1;
    }

    function earn() public {
        (uint128 liquidity,,,,) = pool.positions(getPositionID());
        if (liquidity > 0) pool.burn(minTick, maxTick, liquidity);
        pool.collect(address(this), minTick, maxTick, type(uint128).max, type(uint128).max);
        if (tickScale > 0) {
            (minTick, maxTick) = getTickRange(tickScale, address(pool));
            minSqrtRatio = TickMath.getSqrtRatioAtTick(minTick);
            maxSqrtRatio = TickMath.getSqrtRatioAtTick(maxTick);
        }

        (uint160 midX96,,,,,,) = pool.slot0();
        uint256 bal0 = token0.balanceOf(address(this));
        uint256 bal1 = token1.balanceOf(address(this));
        uint128 liq0 = LiquidityAmounts.getLiquidityForAmount0(midX96, maxSqrtRatio, bal0);
        uint128 liq1 = LiquidityAmounts.getLiquidityForAmount1(minSqrtRatio, midX96, bal1);

        if (liq0 > liq1) {
            uint256 got = LiquidityAmounts.getAmount0ForLiquidity(midX96, maxSqrtRatio, liq1);
            uint256 amt = (bal0 - got) / 2;
            if (strategyHelper.value(address(token0), amt) > 5e17) { //.5$
              token0.approve(address(strategyHelper), amt);
              strategyHelper.swap(address(token0), address(token1), amt, slippage, address(this));
            }
        } else {
            uint256 got = LiquidityAmounts.getAmount1ForLiquidity(minSqrtRatio, midX96, liq0);
            uint256 amt = (bal1 - got) / 2;
            if (strategyHelper.value(address(token0), amt) > 5e17) { //.5$
              token1.approve(address(strategyHelper), amt);
              strategyHelper.swap(address(token1), address(token0), amt, slippage, address(this));
            }
        }

        (uint160 newMidX96,,,,,,) = pool.slot0();
        uint128 liq = LiquidityAmounts.getLiquidityForAmounts(
            newMidX96, minSqrtRatio, maxSqrtRatio, bal0, bal1
        );
        if (liq > 0) pool.mint(address(this), minTick, maxTick, liq, "");
    }

    function uniswapV3SwapCallback(int256 amount0, int256 amount1, bytes calldata) external override {
        require(msg.sender == address(pool));
        if (amount0 > 0) push(token0, msg.sender, uint256(amount0));
        if (amount1 > 0) push(token1, msg.sender, uint256(amount1));
    }

    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata) external override {
        require(msg.sender == address(pool));
        if (amount0 > 0) push(token0, msg.sender, amount0);
        if (amount1 > 0) push(token1, msg.sender, amount1);
    }

    function getPositionID() internal view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), minTick, maxTick));
    }

    function getTickRange(int24 scale, address poolAddress) internal view returns (int24, int24) {
        (, int24 tick,,,,,) = IUniswapV3Pool(poolAddress).slot0();
        int24 scaleMod = tick < 0 ? -int24(1) : int24(1);
        int24 targetMinTick = int24(int256(tick) * (1e5 - (scale * scaleMod)) / 1e5);
        int24 targetMaxTick = int24(int256(tick) * (1e5 + (scale * scaleMod)) / 1e5);
        int24 activeMinTick = TickLib.nearestUsableTick(targetMinTick, tickSpacing);
        int24 activeMaxTick = TickLib.nearestUsableTick(targetMaxTick, tickSpacing);
        return (activeMinTick, activeMaxTick);
    }
}

