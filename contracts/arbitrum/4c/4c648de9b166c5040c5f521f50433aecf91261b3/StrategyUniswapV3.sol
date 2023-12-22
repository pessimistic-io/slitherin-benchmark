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
    using BytesLib for bytes;

    error NoLiquidity();
    error TooLittleReceived();

    string public name;
    IUniswapV3Pool public immutable pool;
    IERC20 public immutable token0;
    IERC20 public immutable token1;
    uint24 public immutable fee;
    int24 public immutable minTick;
    int24 public immutable maxTick;
    uint160 public immutable minSqrtRatio;
    uint160 public immutable maxSqrtRatio;
    IOracle public oracleToken0; // Chainlink for pool token0
    IOracle public oracleToken1; // Chainlink for pool token1
    ISwapRouter public immutable router;
    bytes public path0;
    bytes public path1;

    constructor(
        address _asset,
        address _investor,
        string memory _name,
        address _pool,
        uint24 _fee,
        address _oracleToken0,
        address _oracleToken1,
        address _router,
        bytes memory _path0,
        bytes memory _path1
    )
        Strategy(_asset, _investor)
    {
        name = _name;
        pool = IUniswapV3Pool(_pool);
        token0 = IERC20(IUniswapV3Pool(_pool).token0());
        token1 = IERC20(IUniswapV3Pool(_pool).token1());
        fee = _fee;
        minTick = TickLib.nearestUsableTick(TickMath.MIN_TICK, IUniswapV3Pool(_pool).tickSpacing());
        maxTick = TickLib.nearestUsableTick(TickMath.MAX_TICK, IUniswapV3Pool(_pool).tickSpacing());
        minSqrtRatio = TickMath.getSqrtRatioAtTick(minTick);
        maxSqrtRatio = TickMath.getSqrtRatioAtTick(maxTick);
        oracleToken0 = IOracle(_oracleToken0);
        oracleToken1 = IOracle(_oracleToken1);
        router = ISwapRouter(_router);
        path0 = _path0;
        path1 = _path1;
    }

    function rate(uint256 sha) external view override returns (uint256) {
        uint256 value = 0;
        (uint160 midX96, int24 tick,,,,,) = pool.slot0();
        (
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = pool.positions(_getPositionID());

        uint256 amount0Total;
        uint256 amount1Total;

        {
            (uint256 amount0, uint256 amount1) =
                LiquidityAmounts.getAmountsForLiquidity(midX96, minSqrtRatio, maxSqrtRatio, liquidity);

            (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = TickLib.getFeeGrowthInside(
                address(pool), minTick, maxTick, tick, pool.feeGrowthGlobal0X128(), pool.feeGrowthGlobal1X128()
            );

            uint256 newTokensOwed0 =
                FullMath.mulDiv(feeGrowthInside0X128 - feeGrowthInside0LastX128, liquidity, FixedPoint128.Q128);

            uint256 newTokensOwed1 =
                FullMath.mulDiv(feeGrowthInside1X128 - feeGrowthInside1LastX128, liquidity, FixedPoint128.Q128);

            amount0Total = amount0 + uint256(tokensOwed0) + newTokensOwed0;
            amount1Total = amount1 + uint256(tokensOwed1) + newTokensOwed1;
        }

        {
            uint256 decimals = token0.decimals();
            uint256 oracleDecimals = oracleToken0.decimals();
            uint256 price = uint256(oracleToken0.latestAnswer());

            value += ((amount0Total * price) / 10 ** oracleDecimals) / 10 ** (decimals - 6);
        }
        {
            uint256 decimals = token1.decimals();
            uint256 oracleDecimals = oracleToken1.decimals();
            uint256 price = uint256(oracleToken1.latestAnswer());

            value += ((amount1Total * price) / 10 ** oracleDecimals) / 10 ** (decimals - 6);
        }

        return sha * value / totalShares;
    }

    function _mint(uint256 amt) internal override returns (uint256) {
        earn();

        uint256 price0 = uint256(oracleToken0.latestAnswer());
        uint256 price1 = uint256(oracleToken1.latestAnswer());
        uint256 half = amt / 2;
        if (address(token0) == address(asset)) {
            uint256 minAmount =
                ((half * (10 ** (token1.decimals() + oracleToken1.decimals() - 6)) / price1) * slippage) / bipsDivisor;
            (, int256 amount1) = pool.swap(address(this), true, int256(half), minSqrtRatio + 1, "");
            if (uint256(-amount1) < minAmount) {
                revert TooLittleReceived();
            }
        } else if (address(token1) == address(asset)) {
            uint256 minAmount =
                ((half * (10 ** (token0.decimals() + oracleToken0.decimals() - 6)) / price0) * slippage) / bipsDivisor;

            (int256 amount0,) = pool.swap(address(this), false, int256(half), maxSqrtRatio - 1, "");
            if (uint256(-amount0) < minAmount) {
                revert TooLittleReceived();
            }
        } else {
            asset.approve(address(router), amt);
            uint256 minAmount0 =
                ((half * (10 ** (token0.decimals() + oracleToken0.decimals() - 6)) / price0) * slippage) / bipsDivisor;
            if (path0.length > 0) {
                ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
                    path: path0,
                    recipient: address(this),
                    deadline: type(uint256).max,
                    amountIn: half,
                    amountOutMinimum: minAmount0
                });
                router.exactInput(params);
            }

            uint256 minAmount1 = (
                ((amt - half) * (10 ** (token1.decimals() + oracleToken1.decimals() - 6)) / price1) * slippage
            ) / bipsDivisor;
            if (path1.length > 0) {
                ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
                    path: path1,
                    recipient: address(this),
                    deadline: type(uint256).max,
                    amountIn: amt - half,
                    amountOutMinimum: minAmount1
                });
                router.exactInput(params);
            }
        }

        (uint128 tma,,,,) = pool.positions(_getPositionID());
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        (uint160 midX96,,,,,,) = pool.slot0();

        uint128 newLiquidity =
            LiquidityAmounts.getLiquidityForAmounts(midX96, minSqrtRatio, maxSqrtRatio, balance0, balance1);

        if (newLiquidity == 0) {
            revert NoLiquidity();
        }

        pool.mint(address(this), minTick, maxTick, newLiquidity, "");

        return tma == 0 ? newLiquidity : newLiquidity * totalShares / tma;
    }

    function _burn(uint256 sha) internal override returns (uint256) {
        earn();
        (uint128 tma,,,,) = pool.positions(_getPositionID());
        uint128 liquidityShare = uint128(sha) * tma / uint128(totalShares);

        if (liquidityShare > 0) {
            pool.burn(minTick, maxTick, liquidityShare);
        }

        pool.collect(address(this), minTick, maxTick, type(uint128).max, type(uint128).max);

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        uint256 price0 = uint256(oracleToken0.latestAnswer());
        uint256 price1 = uint256(oracleToken1.latestAnswer());

        if (address(token0) == address(asset)) {
            int256 swapAmount = int256(balance1);

            if (swapAmount > 0) {
                uint256 minAmount = (
                    ((balance1 * price1) / 10 ** oracleToken1.decimals()) / 10 ** (token1.decimals() - 6) * slippage
                ) / bipsDivisor;
                (int256 amount0,) = pool.swap(address(this), false, swapAmount, maxSqrtRatio - 1, "");
                if (uint256(-amount0) < minAmount) {
                    revert TooLittleReceived();
                }
            }
        } else if (address(token1) == address(asset)) {
            int256 swapAmount = int256(balance0);

            if (swapAmount > 0) {
                uint256 minAmount = (
                    ((balance0 * price0) / 10 ** oracleToken0.decimals()) / 10 ** (token0.decimals() - 6) * slippage
                ) / bipsDivisor;
                (, int256 amount1) = pool.swap(address(this), true, swapAmount, minSqrtRatio + 1, "");
                if (uint256(-amount1) < minAmount) {
                    revert TooLittleReceived();
                }
            }
        } else {
            if (balance0 > 0 && path0.length > 0) {
                token0.approve(address(router), balance0);
                uint256 minAmount = (
                    ((balance0 * price0) / 10 ** oracleToken0.decimals()) / 10 ** (token0.decimals() - 6) * slippage
                ) / bipsDivisor;
                ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
                    path: _reversePath(path0),
                    recipient: address(this),
                    deadline: type(uint256).max,
                    amountIn: balance0,
                    amountOutMinimum: minAmount
                });
                router.exactInput(params);
            }

            if (balance1 > 0 && path1.length > 0) {
                token1.approve(address(router), balance1);
                uint256 minAmount = (
                    ((balance1 * price1) / 10 ** oracleToken1.decimals()) / 10 ** (token1.decimals() - 6) * slippage
                ) / bipsDivisor;
                ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
                    path: _reversePath(path1),
                    recipient: address(this),
                    deadline: type(uint256).max,
                    amountIn: balance1,
                    amountOutMinimum: minAmount
                });
                router.exactInput(params);
            }
        }

        return asset.balanceOf(address(this));
    }

    function earn() public {
        (uint128 liquidity,,,,) = pool.positions(_getPositionID());

        uint256 preBalance0 = token0.balanceOf(address(this));
        uint256 preBalance1 = token1.balanceOf(address(this));

        if (liquidity > 0) {
            pool.burn(minTick, maxTick, liquidity);
        }

        pool.collect(address(this), minTick, maxTick, type(uint128).max, type(uint128).max);

        (uint160 midX96,,,,,,) = pool.slot0();
        uint256 balance0 = token0.balanceOf(address(this)) - preBalance0;
        uint256 balance1 = token1.balanceOf(address(this)) - preBalance1;
        uint128 liq0 = LiquidityAmounts.getLiquidityForAmount0(midX96, maxSqrtRatio, balance0);
        uint128 liq1 = LiquidityAmounts.getLiquidityForAmount1(minSqrtRatio, midX96, balance1);

        uint256 price0 = uint256(oracleToken0.latestAnswer());
        uint256 price1 = uint256(oracleToken1.latestAnswer());
        uint256 price = price1 * 1e18 / price0;
        int8 baseAdjust = int8(18) + int8(token1.decimals()) - int8(token0.decimals());

        if (liq0 > liq1) {
            uint256 got = LiquidityAmounts.getAmount0ForLiquidity(midX96, maxSqrtRatio, liq1);
            int256 swapAmount = int256((balance0 - got) / 2);
            uint256 minSwapAmount = 1e7 * (10 ** token0.decimals()) / price0;

            if (swapAmount > int256(minSwapAmount)) {
                uint256 minAmount =
                    ((uint256(swapAmount) * (10 ** uint256(int256(baseAdjust))) / price) * slippage) / bipsDivisor;
                (, int256 amount1) = pool.swap(address(this), true, swapAmount, minSqrtRatio + 1, "");
                if (uint256(-amount1) < minAmount) {
                    revert TooLittleReceived();
                }
            }
        } else {
            uint256 got = LiquidityAmounts.getAmount1ForLiquidity(minSqrtRatio, midX96, liq0);
            int256 swapAmount = int256((balance1 - got) / 2);
            uint256 minSwapAmount = 1e7 * (10 ** token1.decimals()) / price1;

            if (swapAmount > int256(minSwapAmount)) {
                uint256 minAmount =
                    (((uint256(swapAmount) * price) / 10 ** uint256(int256(baseAdjust))) * slippage) / bipsDivisor;
                (int256 amount0,) = pool.swap(address(this), false, swapAmount, maxSqrtRatio - 1, "");
                if (uint256(-amount0) < minAmount) {
                    revert TooLittleReceived();
                }
            }
        }

        balance0 = token0.balanceOf(address(this)) - preBalance0;
        balance1 = token1.balanceOf(address(this)) - preBalance1;
        (uint160 newMidX96,,,,,,) = pool.slot0();

        uint128 newLiquidity =
            LiquidityAmounts.getLiquidityForAmounts(newMidX96, minSqrtRatio, maxSqrtRatio, balance0, balance1);

        if (newLiquidity > 0) {
            pool.mint(address(this), minTick, maxTick, newLiquidity, "");
        }
    }

    function uniswapV3SwapCallback(int256 amount0, int256 amount1, bytes calldata) external override {
        require(msg.sender == address(pool));
        if (amount0 > 0) {
            _push(address(token0), msg.sender, uint256(amount0));
        }
        if (amount1 > 0) {
            _push(address(token1), msg.sender, uint256(amount1));
        }
    }

    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata) external override {
        require(msg.sender == address(pool));
        if (amount0 > 0) {
            _push(address(token0), msg.sender, amount0);
        }
        if (amount1 > 0) {
            _push(address(token1), msg.sender, amount1);
        }
    }

    function _getPositionID() internal view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), minTick, maxTick));
    }

    function _reversePath(bytes memory path) internal pure returns (bytes memory reversedPath) {
        uint256 offset = 20;
        uint256 start = path.length - offset;

        while (true) {
            reversedPath = bytes.concat(reversedPath, path.slice(start, offset));

            if (reversedPath.length == path.length) {
                break;
            }

            offset = offset == 20 ? 3 : 20;
            start -= offset;
        }
    }
}

