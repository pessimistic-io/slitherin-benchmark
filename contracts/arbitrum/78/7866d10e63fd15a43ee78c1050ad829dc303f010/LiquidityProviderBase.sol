// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {IUniV3Pool} from "./IUniV3Pool.sol";
import {IUniV3Callback} from "./IUniV3Callback.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";
import {FeeMath} from "./FeeMath.sol";
import {Math} from "./Math.sol";
import {Oracle} from "./Oracle.sol";
import {FullMath} from "./FullMath.sol";
import {TickMath} from "./TickMath.sol";
import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";

abstract contract LiquidityProviderBase is IUniV3Callback {
    using SafeTransferLib for ERC20;
    using Oracle for IUniV3Pool;

    ERC20 public immutable token0;
    ERC20 public immutable token1;
    int24 public tickLower;
    int24 public tickUpper;
    uint128 public totalLiquidity;
    uint256 public balance0;
    uint256 public balance1;
    uint32 public lastCompoundTime;
    uint256 public maxPoolApy = 100;
    uint256 public maxSlippage = 25; // 0.25% slippage
    uint32 public slippageMA = 1 minutes;
    address public treasury;
    address public controller;

    event ControllerUpdated(address controller);
    event TreasuryUpdated(address treasury);
    event SetMaxApy(uint256 maxApy);
    event SetMaxSlippage(uint256 maxSlippage);
    event SetSlippageMovingAverage(uint32 slippageMovingAverage);

    // Basic slippage protection.
    modifier stablePrice() {
        (, int24 currentTick,,,,,) = pool().slot0();
        int24 tickMovingAverage = getMovingAverage(slippageMA);
        require(Math.diff(currentTick, tickMovingAverage) < maxSlippage, "VOLATILE_PRICE");
        _;
    }

    modifier requireSender(address requiredSender) {
        require(msg.sender == requiredSender, "UNAUTHORIZED");
        _;
    }

    constructor(address uniV3Pool, int24 _tickLower, int24 _tickUpper) {
        token0 = ERC20(IUniV3Pool(uniV3Pool).token0());
        token1 = ERC20(IUniV3Pool(uniV3Pool).token1());
        require(_tickLower % IUniV3Pool(uniV3Pool).tickSpacing() == 0, "TICK_LOWER_INVALID");
        require(_tickUpper % IUniV3Pool(uniV3Pool).tickSpacing() == 0, "TICK_UPPER_INVALID");
        tickLower = _tickLower;
        tickUpper = _tickUpper;
        treasury = msg.sender;
        controller = msg.sender;
    }

    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data)
        external
        requireSender(address(pool()))
    {
        address sender = abi.decode(data, (address));
        if (sender == address(this)) {
            token0.safeTransfer(msg.sender, amount0Owed);
            token1.safeTransfer(msg.sender, amount1Owed);
            balance0 -= amount0Owed;
            balance1 -= amount1Owed;
        } else {
            uint256 send0 = Math.min(balance0, amount0Owed);
            if (send0 > 0) {
                token0.safeTransfer(msg.sender, send0);
                amount0Owed -= send0;
                balance0 -= send0;
            }
            uint256 send1 = Math.min(balance1, amount1Owed);
            if (send1 > 0) {
                token1.safeTransfer(msg.sender, send1);
                amount1Owed -= send1;
                balance1 -= send1;
            }
            token0.safeTransferFrom(sender, msg.sender, amount0Owed);
            token1.safeTransferFrom(sender, msg.sender, amount1Owed);
        }
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data)
        external
        requireSender(address(pool()))
    {
        address sender = abi.decode(data, (address));
        if (sender == address(this)) {
            if (amount0Delta > 0) {
                token0.safeTransfer(msg.sender, uint256(amount0Delta));
                balance0 -= uint256(amount0Delta);
            } else if (amount1Delta > 0) {
                token1.safeTransfer(msg.sender, uint256(amount1Delta));
                balance1 -= uint256(amount1Delta);
            }
        } else {
            if (amount0Delta > 0) {
                token0.safeTransferFrom(sender, msg.sender, uint256(amount0Delta));
            } else if (amount1Delta > 0) {
                token1.safeTransferFrom(sender, msg.sender, uint256(amount1Delta));
            }
        }
    }

    function setTreasury(address _treasury) external requireSender(treasury) {
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    function setController(address _controller) external requireSender(controller) {
        controller = _controller;
        emit ControllerUpdated(_controller);
    }

    function setMaxPoolApy(uint256 _maxPoolApy) external requireSender(controller) {
        maxPoolApy = _maxPoolApy;
        emit SetMaxApy(_maxPoolApy);
    }

    function setMaxSlippage(uint256 _maxSlippage) external requireSender(controller) {
        maxSlippage = _maxSlippage;
        emit SetMaxSlippage(_maxSlippage);
    }

    function setSlippageMA(uint32 _slippageMa) external requireSender(controller) {
        slippageMA = _slippageMa;
        emit SetSlippageMovingAverage(_slippageMa);
    }

    function skim(ERC20 token) external requireSender(treasury) {
        uint256 balance = token.balanceOf(address(this));
        if (token == token0) {
            token0.safeTransfer(treasury, balance - balance0);
        } else if (token == token1) {
            token1.safeTransfer(treasury, balance - balance1);
        } else {
            token.safeTransfer(treasury, balance);
        }
    }

    function pool() public view virtual returns (IUniV3Pool);

    function getPosition()
        public
        view
        returns (
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        bytes32 key = keccak256(abi.encodePacked(address(this), tickLower, tickUpper));
        return pool().positions(key);
    }

    function getMovingAverage(uint32 duration) public view returns (int24 tick) {
        return pool().getMovingAverage(duration);
    }

    function getAmountsForLiquidity(uint128 liquidity, uint160 price) public view returns (uint256 amount0, uint256 amount1) {
        (uint160 sqrtRatioAX96, uint160 sqrtRatioBX96) = getRangePrices();
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(price, sqrtRatioAX96, sqrtRatioBX96, liquidity);
    }

    function getAmountsForLiquidity(uint128 liquidity) public view returns (uint256 amount0, uint256 amount1) {
        return getAmountsForLiquidity(liquidity, getCurrentPrice());
    }

    // Get unclaimed fees by the position. The fees are limited by the maxPoolApy.
    function getUnclaimedFees() public view returns (uint256 amount0, uint256 amount1) {
        (, uint256 feeGrowthInside0Last, uint256 feeGrowthInside1Last,,) = getPosition();
        (, int24 currentTick,,,,,) = pool().slot0();
        (,, uint256 l_feeGrowthOutside0, uint256 l_feeGrowthOutside1,,,,) = pool().ticks(tickLower);
        (,, uint256 u_feeGrowthOutside0, uint256 u_feeGrowthOutside1,,,,) = pool().ticks(tickUpper);
        (uint256 feeGrowthInside0, uint256 feeGrowthInside1) = FeeMath.getFeeGrowthInside(
            tickLower,
            tickUpper,
            currentTick,
            pool().feeGrowthGlobal0X128(),
            pool().feeGrowthGlobal1X128(),
            l_feeGrowthOutside0,
            l_feeGrowthOutside1,
            u_feeGrowthOutside0,
            u_feeGrowthOutside1
        );
        (amount0, amount1) = FeeMath.getPendingFees(
            totalLiquidity, feeGrowthInside0Last, feeGrowthInside1Last, feeGrowthInside0, feeGrowthInside1
        );
        (uint256 max0, uint256 max1) = getMaxFees();
        amount0 = amount0 > max0 ? max0 : amount0;
        amount1 = amount1 > max1 ? max1 : amount1;
    }

    function inRange() public view returns (bool) {
        uint160 sqrtRatioX96 = getCurrentPrice();
        (uint160 sqrtRatioAX96, uint160 sqrtRatioBX96) = getRangePrices();
        return sqrtRatioAX96 < sqrtRatioX96 && sqrtRatioX96 < sqrtRatioBX96;
    }

    // Calculate the amount of liquidity that can be directly added to the current position given two asset amounts.
    // Returns the amount of liquidity and whether the token1 amount remains.
    function mintLiquidityPreview(uint256 amount0, uint256 amount1)
        public
        view
        returns (uint128 liquidity, bool token1Remains)
    {
        uint160 sqrtRatioX96 = getCurrentPrice();
        (uint160 sqrtRatioAX96, uint160 sqrtRatioBX96) = getRangePrices();
        if (sqrtRatioX96 <= sqrtRatioAX96) {
            liquidity = LiquidityAmounts.getLiquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, amount0);
            token1Remains = true;
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            uint128 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(sqrtRatioX96, sqrtRatioBX96, amount0);
            uint128 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioX96, amount1);
            token1Remains = liquidity0 < liquidity1;
            liquidity = token1Remains ? liquidity0 : liquidity1;
        } else {
            liquidity = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, amount1);
            token1Remains = false;
        }
    }

        // Returns the amount we need to swap to add the maximum amount of liquidity, starting with two assets.
    function mintMaxLiquidityPreview(uint256 startingAmount0, uint256 startingAmount1)
        public
        view
        returns (uint256 amountToSwap, bool zeroForOne)
    {
        (uint128 liquidity, bool token1Remains) = mintLiquidityPreview(startingAmount0, startingAmount1);
        (uint256 amount0, uint256 amount1) = getAmountsForLiquidity(liquidity);
        zeroForOne = !token1Remains;
        amountToSwap =
            onesidedMintPreview(token1Remains ? startingAmount1 - amount1 : startingAmount0 - amount0, zeroForOne);
    }

    // Returns the amount we need to swap to add the maximum amount of liquidity, starting with only one asset.
    function onesidedMintPreview(uint256 startingAmount, bool isToken0) public view returns (uint256 amountToSwap) {
        uint160 sqrtRatioX96 = getCurrentPrice();
        (uint160 sqrtRatioAX96, uint160 sqrtRatioBX96) = getRangePrices();
        uint256 invFee = (1e6 - pool().fee());
        // Calculate amount to swap assuming no price impact.
        amountToSwap = _calculateAmountToSwap(
            startingAmount, isToken0, sqrtRatioX96, sqrtRatioX96, sqrtRatioAX96, sqrtRatioBX96, invFee
        );
        // Estimate price impact.
        uint160 nextSqrtRatioX96 = _estimatePriceChange(amountToSwap, isToken0, sqrtRatioX96);
        // Recalculate amount to swap based on the expected price impact.
        amountToSwap = _calculateAmountToSwap(
            startingAmount,
            isToken0,
            nextSqrtRatioX96,
            uint160((uint256(nextSqrtRatioX96) + sqrtRatioX96) / 2),
            sqrtRatioAX96,
            sqrtRatioBX96,
            invFee
        );
    }

    // Returns the amount we need to swap to add maximum liquidity, starting with one asset.
    // sqrtRangeRatioX96 is the price of the pool.
    // sqrtPriceRatioX96 is the price we expact to get for the swap.
    // Formula (solve for swapAmount): price * swapAmount / (startingAmount - swapAmount) == rangeRatio
    function _calculateAmountToSwap(
        uint256 startingAmount,
        bool zeroForOne,
        uint160 sqrtRangeRatioX96,
        uint160 sqrtPriceRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 invFee
    ) internal pure returns (uint256 amount) {
        (uint256 rangeRatio0, uint256 rangeRatio1) =
            LiquidityAmounts.getAmountsForLiquidity(sqrtRangeRatioX96, sqrtRatioAX96, sqrtRatioBX96, 1e18);
        (uint256 priceRatio0, uint256 priceRatio1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceRatioX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO, 1e18
        );
        if (zeroForOne) {
            amount = (startingAmount * rangeRatio1 / rangeRatio0) * 1e18
                / (1e12 * invFee * priceRatio1 / priceRatio0 + 1e18 * rangeRatio1 / rangeRatio0);
        } else {
            amount = (startingAmount * rangeRatio0 / rangeRatio1) * 1e18
                / (1e12 * invFee * priceRatio0 / priceRatio1 + 1e18 * rangeRatio0 / rangeRatio1);
        }
    }

    function estimatePriceChange(uint256 amountIn, bool zeroForOne) public view returns (uint160 currentPrice, uint160 nextPrice) {
        (currentPrice,,,,,,) = pool().slot0();
        nextPrice = _estimatePriceChange(amountIn, zeroForOne, currentPrice);
    }

    // We set a ceiling to the pool APY to prevent the LP token price inflation attack vector.
    function getMaxFees() public view returns (uint256 amount0, uint256 amount1) {
        (uint256 invested0, uint256 invested1) = getAmountsForLiquidity(totalLiquidity);
        uint256 passedTime = 1 + (block.timestamp - lastCompoundTime);
        amount0 = (invested0 * maxPoolApy / 100) * passedTime / 365 days;
        amount1 = (invested1 * maxPoolApy / 100) * passedTime / 365 days;
    }

    function getCurrentPrice() public view returns (uint160 sqrtRatioX96) {
        (sqrtRatioX96,,,,,,) = pool().slot0();
    }

    function getRangePrices() public view returns (uint160 sqrtRatioAX96, uint160 sqrtRatioBX96) {
        sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
    }

    function _estimatePriceChange(uint256 amountIn, bool zeroForOne, uint160 currentPrice) internal view returns (uint160 nextPrice) {
        uint256 liquidity = pool().liquidity();
        if (zeroForOne) {
            uint256 liq = liquidity << 96;
            nextPrice = uint160(FullMath.mulDiv(liq, currentPrice, liq + amountIn * currentPrice));
        } else {
            nextPrice = uint160(currentPrice + (amountIn << 96) / liquidity);
        }
    }

    function _addLiquidity(uint128 liquidity, address sender) internal returns (uint256 amount0, uint256 amount1) {
        if (liquidity == 0) return (0, 0);
        (amount0, amount1) = pool().mint(address(this), tickLower, tickUpper, liquidity, abi.encode(sender));
        totalLiquidity += liquidity;
    }

    function _removeLiquidity(uint128 liquidity, address recipient)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        pool().burn(tickLower, tickUpper, liquidity);
        totalLiquidity -= liquidity;
        (amount0, amount1) = pool().collect(recipient, tickLower, tickUpper, type(uint128).max, type(uint128).max);
        if (recipient == address(this)) {
            balance0 += amount0;
            balance1 += amount1;
        }
    }

    function _compound() internal stablePrice returns (uint256 amount0, uint256 amount1, uint128 liquidityAdded) {
        if (totalLiquidity == 0 || lastCompoundTime == block.timestamp) return (0, 0, 0);
        (uint256 fees0, uint256 fees1) = _removeLiquidity(0, address(this));
        (uint256 maxFees0, uint256 maxFees1) = getMaxFees();
        if (fees0 > maxFees0) balance0 -= fees0 - maxFees0;
        if (fees1 > maxFees1) balance1 -= fees1 - maxFees1;
        lastCompoundTime = uint32(block.timestamp);
        (amount0, amount1, liquidityAdded,) = _addMaxLiquidity(0);
    }

    function _addAvailableLiquidity()
        internal
        returns (uint256 amount0, uint256 amount1, uint128 liquidityAdded, bool token1Remains)
    {
        (liquidityAdded, token1Remains) = mintLiquidityPreview(balance0, balance1);
        (amount0, amount1) = _addLiquidity(liquidityAdded, address(this));
    }

    function _addMaxLiquidity(uint128 minLiquidityAdded)
        internal
        returns (uint256 amount0, uint256 amount1, uint128 liquidityAdded, bool token1Remains)
    {
        if (inRange()) {
            (uint256 amountToSwap, bool zeroForOne) = mintMaxLiquidityPreview(balance0, balance1);
            _swap(zeroForOne, amountToSwap, 0, address(this), address(this));
        }
        (amount0, amount1, liquidityAdded, token1Remains) = _addAvailableLiquidity();
        require(liquidityAdded >= minLiquidityAdded, "Not enough liquidity added");
    }

    function _swap(bool zeroForOne, uint256 amountIn, uint256 minimumAmountOut, address sender, address recipient)
        internal
        returns (uint256 amountOut)
    {
        if (amountIn == 0) return 0;
        (int256 a, int256 b) = pool().swap(
            recipient,
            zeroForOne,
            int256(amountIn),
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            abi.encode(sender)
        );
        if (zeroForOne) {
            amountOut = uint256(-b);
            if (recipient == address(this)) balance1 += amountOut;
        } else {
            amountOut = uint256(-a);
            if (recipient == address(this)) balance0 += amountOut;
        }
        require(amountOut >= minimumAmountOut);
    }
}

