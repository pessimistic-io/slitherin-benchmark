// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./SafeTransferLib.sol";
import "./IUniswapV3Pool.sol";
import "./IUniswapV2Pool.sol";
import "./UniV3Math.sol";
import "./LiquidityAmounts.sol";
import "./PositionKey.sol";
import "./UniOracle.sol";
import "./Base.sol";

contract UniswapActions is Base {
    using SafeTransferLib for ERC20;

    IUniswapV3Pool internal immutable _pool;
    int24 internal immutable _tickSpacing;
    ERC20 internal immutable _token0;
    ERC20 internal immutable _token1;
    uint24 internal _rangeBuffer;
    int24 internal _distanceLower;
    int24 internal _distanceUpper;
    int24 internal _tickLower;
    int24 internal _tickUpper;
    uint32 internal _movingAverageDuration;

    constructor(
        address pool,
        uint24 rangeBuffer,
        int24 distanceLower,
        int24 distanceUpper,
        uint32 movingAverageDuration
    ) {
        _pool = IUniswapV3Pool(pool);
        _tickSpacing = _pool.tickSpacing();
        _token0 = ERC20(_pool.token0());
        _token1 = ERC20(_pool.token1());
        _rangeBuffer = rangeBuffer;
        _distanceLower = distanceLower;
        _distanceUpper = distanceUpper;
        _movingAverageDuration = movingAverageDuration;
        (_tickLower, _tickUpper) = getIdealRange();
    }

    function getLiquidityProviderData()
        external
        view
        returns (
            uint24 rangeBuffer,
            int24 distanceLower,
            int24 distanceUpper,
            int24 tickLower,
            int24 tickUpper,
            uint32 movingAverageDuration,
            int24 currentTick,
            uint128 positionLiquidity,
            uint128 totalLiquidity
        )
    {
        rangeBuffer = _rangeBuffer;
        distanceLower = _distanceLower;
        distanceUpper = _distanceUpper;
        tickLower = _tickLower;
        tickUpper = _tickUpper;
        (, currentTick,,,,,) = _pool.slot0();
        movingAverageDuration = _movingAverageDuration;
        totalLiquidity = _pool.liquidity();
        positionLiquidity = getLiquidity();
    }

    function getCurrentTick() public view returns (int24 currentTick) {
        (, currentTick,,,,,) = _pool.slot0();
    }

    function getLiquidity() public view returns (uint128 liquidity) {
        (liquidity,,,,) = _pool.positions(PositionKey.compute(address(this), _tickLower, _tickUpper));
    }

    function getUnclaimedFees() public view returns (uint256 amount0, uint256 amount1) {
        (uint128 liquidity, uint256 feeGrowthInside0Last, uint256 feeGrowthInside1Last,,) =
            _pool.positions(PositionKey.compute(address(this), _tickLower, _tickUpper));
        int24 currentTick = getCurrentTick();
        (,, uint256 l_feeGrowthOutside0, uint256 l_feeGrowthOutside1,,,,) = _pool.ticks(_tickLower);
        (,, uint256 u_feeGrowthOutside0, uint256 u_feeGrowthOutside1,,,,) = _pool.ticks(_tickUpper);
        (uint256 feeGrowthInside0, uint256 feeGrowthInside1) = UniV3Math.getFeeGrowthInside(
            _tickLower,
            _tickUpper,
            currentTick,
            _pool.feeGrowthGlobal0X128(),
            _pool.feeGrowthGlobal1X128(),
            l_feeGrowthOutside0,
            l_feeGrowthOutside1,
            u_feeGrowthOutside0,
            u_feeGrowthOutside1
        );
        return UniV3Math.getPendingFees(
            liquidity, feeGrowthInside0Last, feeGrowthInside1Last, feeGrowthInside0, feeGrowthInside1
        );
    }

    // We use a 1day moving average to calculate the range position.
    function getIdealRange() public view returns (int24 lower, int24 upper) {
        int24 maTick = UniOracle.getTick(_pool, 24 * 60 * 60);
        maTick = maTick - (maTick % _tickSpacing);
        lower = maTick - _distanceLower;
        upper = maTick + _distanceUpper;
    }

    function getNextRange() public view returns (bool needsToUpdate, int24 lower, int24 upper) {
        (int24 idealLower, int24 idealUpper) = getIdealRange();
        needsToUpdate = diff(idealLower, _tickLower) > _rangeBuffer || diff(idealUpper, _tickUpper) > _rangeBuffer;
        (lower, upper) = needsToUpdate ? (idealLower, idealUpper) : (_tickLower, _tickUpper);
    }

    // Similar to uniswap a v2 getReserves call.
    // Used to calculate the current price of the assets. (amount0 / amount1) or (amount1 / amount0).
    function getReserveRatio() public view returns (uint256 amount0, uint256 amount1) {
        int24 tick = getCurrentTick();
        (amount0, amount1) = _getAmountsForLiquidity(tick - 1000, tick + 1000, 1e18);
    }

    // Makes two assumtions:
    // 1. One of the amounts is near zero
    // 2. There is no slippage
    function getLiquidityAditionSwapParams(uint256 amount0, uint256 amount1)
        public
        view
        returns (bool zeroForOne, uint256 amountIn)
    {
        uint256 positionRatio = getRangeAssetRatio();
        (uint256 reserve0, uint256 reserve1) = getReserveRatio();
        zeroForOne = amount1 == 0 || (positionRatio < amount0 * 1e18 / amount1);
        if (zeroForOne) {
            amountIn = 1e18 * amount0 / (1e18 + positionRatio * reserve1 / reserve0);
        } else {
            amountIn = 1e18 * amount1 / (1e18 + reserve0 * 1e36 / (reserve1 * positionRatio));
        }
    }

    // Gets a quote for a swap without slippage.
    function getSimpleQuote(bool zeroForOne, uint256 amountIn) public view returns (uint256 amountOut) {
        (uint256 reserve0, uint256 reserve1) = getReserveRatio();
        if (zeroForOne) {
            amountOut = amountIn * reserve1 / reserve0;
        } else {
            amountOut = amountIn * reserve0 / reserve1;
        }
    }

    // ratio > 1e18 means we have to supply more usdc than eth (in terms of dollar value) to our univ3 position.
    // todo private?
    function getValueRatio(bool wethIsZero) public view returns (uint256 valueRatio) {
        uint256 ratio = getRangeAssetRatio();
        (uint256 reserve0, uint256 reserve1) = getReserveRatio();
        if (wethIsZero) {
            valueRatio = (1e36 * reserve0 / reserve1) / ratio;
        } else {
            valueRatio = ratio * reserve1 / reserve0;
        }
    }

    // ratio > 1e18 means we have to supply more token0 units than token1 units to our univ3 position.
    function getRangeAssetRatio() public view returns (uint256) {
        (uint160 sqrtPriceX96,,,,,,) = _pool.slot0();
        uint160 sqrtRatioAX96 = UniV3Math.getSqrtRatioAtTick(_tickLower);
        uint160 sqrtRatioBX96 = UniV3Math.getSqrtRatioAtTick(_tickUpper);
        (uint256 amount0, uint256 amount1) =
            LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, 1e18);
        return amount0 * 1e18 / amount1;
    }

    function matchAmountForAmount(bool isZero, uint256 amountA) public view returns (uint256 amountB) {
        (uint160 sqrtPriceX96,,,,,,) = _pool.slot0();
        uint160 sqrtRatioAX96 = UniV3Math.getSqrtRatioAtTick(_tickLower);
        uint160 sqrtRatioBX96 = UniV3Math.getSqrtRatioAtTick(_tickUpper);
        if (isZero) {
            uint128 liquidity = LiquidityAmounts.getLiquidityForAmount0(sqrtPriceX96, sqrtRatioBX96, amountA);
            amountB = LiquidityAmounts.getAmount1ForLiquidity(sqrtRatioAX96, sqrtPriceX96, liquidity);
        } else {
            uint128 liquidity = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, sqrtPriceX96, amountA);
            amountB = LiquidityAmounts.getAmount0ForLiquidity(sqrtPriceX96, sqrtRatioBX96, liquidity);
        }
    }

    function assetsInV3Average() public view returns (uint256 amount0, uint256 amount1) {
        int24 tick = UniOracle.getTick(_pool, _movingAverageDuration);
        uint160 price = UniV3Math.getSqrtRatioAtTick(tick);
        return _assetsInV3(price);
    }

    function assetsInV3Exact() public view returns (uint256 amount0, uint256 amount1) {
        (uint160 sqrtPriceX96,,,,,,) = _pool.slot0();
        return _assetsInV3(sqrtPriceX96);
    }

    function setLiquidityProviderParameters(
        uint32 movingAverageDuration,
        int24 distanceLower,
        int24 distanceUpper,
        uint24 rangeBuffer
    ) external onlyAuthorised {
        require(distanceLower > 0 && distanceUpper > 0, "gt0");
        require(distanceLower % _tickSpacing == 0, "tick spacing lower");
        require(distanceUpper % _tickSpacing == 0, "tick spacing upper");
        _movingAverageDuration = movingAverageDuration;
        _distanceLower = distanceLower;
        _distanceUpper = distanceUpper;
        _rangeBuffer = rangeBuffer;
    }

    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata) external {
        require(msg.sender == address(_pool), "nok");
        if (amount0Owed > 0) _token0.safeTransfer(address(_pool), amount0Owed);
        if (amount1Owed > 0) _token1.safeTransfer(address(_pool), amount1Owed);
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        require(msg.sender == address(_pool), "nok");
        if (amount0Delta > 0) _token0.safeTransfer(address(_pool), uint256(amount0Delta));
        if (amount1Delta > 0) _token1.safeTransfer(address(_pool), uint256(amount1Delta));
    }

    function _assetsInV3(uint160 sqrtPriceX96) internal view returns (uint256 amount0, uint256 amount1) {
        uint160 sqrtRatioAX96 = UniV3Math.getSqrtRatioAtTick(_tickLower);
        uint160 sqrtRatioBX96 = UniV3Math.getSqrtRatioAtTick(_tickUpper);
        uint128 liquidity = getLiquidity();
        (amount0, amount1) =
            LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, liquidity);
        (uint256 fees0, uint256 fees1) = getUnclaimedFees();
        amount0 += fees0;
        amount1 += fees1;
    }

    function _addLiquidity(uint256 amount0Desired, uint256 amount1Desired, uint128 min)
        internal
        returns (uint256 amount0, uint256 amount1, uint128 liquidityMinted)
    {
        liquidityMinted = _getLiquidityForAmounts(_tickLower, _tickUpper, amount0Desired, amount1Desired);
        if (liquidityMinted > 0) {
            (amount0, amount1) = _pool.mint(address(this), _tickLower, _tickUpper, liquidityMinted, "");
        }
        require(liquidityMinted >= min, "liq slippage");
    }

    function _removeLiquidity(uint128 desiredAmount)
        internal
        returns (uint128 liquidityRemoved, uint256 amount0, uint256 amount1)
    {
        uint128 availableLquidity = getLiquidity();
        liquidityRemoved = availableLquidity > desiredAmount ? desiredAmount : availableLquidity;
        (amount0, amount1) = _pool.burn(_tickLower, _tickUpper, liquidityRemoved);
        _pool.collect(address(this), _tickLower, _tickUpper, type(uint128).max, type(uint128).max);
    }

    function _collectFees() internal returns (uint128 amount0, uint128 amount1) {
        (uint128 liquidity,,,,) = _pool.positions(PositionKey.compute(address(this), _tickLower, _tickUpper));
        if (liquidity > 0) _pool.burn(_tickLower, _tickUpper, 0);
        (amount0, amount1) = _pool.collect(address(this), _tickLower, _tickUpper, type(uint128).max, type(uint128).max);
    }

    function _swap(bool zeroForOne, uint256 amountIn, uint256 minimumAmountOut) internal returns (uint256 amountOut) {
        (int256 delta0, int256 delta1) = _pool.swap(
            address(this),
            zeroForOne,
            int256(amountIn),
            zeroForOne ? UniV3Math.MIN_SQRT_RATIO + 1 : UniV3Math.MAX_SQRT_RATIO - 1,
            ""
        );
        amountOut = uint256(zeroForOne ? -delta1 : -delta0);
        require(amountOut >= minimumAmountOut);
    }

    /// @dev Should be called after _collectFees.
    // Removes liquidity and resets the range. Does not add liquidity.
    function _resetRange() internal returns (uint256 amount0, uint256 amount1, uint128 liquidity) {
        (bool shouldUpdate, int24 nextTickLower, int24 nextTickUpper) = getNextRange();
        if (shouldUpdate) {
            liquidity = getLiquidity();
            if (liquidity > 0) (, amount0, amount1) = _removeLiquidity(liquidity);
            (_tickLower, _tickUpper) = (nextTickLower, nextTickUpper);
        }
    }

    function _addMaxLiquidity(uint128 min) internal returns (uint256 amount0, uint256 amount1, uint128 liquidity) {
        (uint256 balance0, uint256 balance1) = (_token0.balanceOf(address(this)), _token1.balanceOf(address(this)));
        (uint256 _amount0, uint256 _amount1, uint128 _liquidity) = _addLiquidity(balance0, balance1, 0);
        (uint256 __amount0, uint256 __amount1, uint128 __liquidity) =
            _swapAndAddLiquidity(balance0 - _amount0, balance1 - _amount1);
        amount0 = _amount0 + __amount0;
        amount1 = _amount1 + __amount1;
        liquidity = _liquidity + __liquidity;
        require(liquidity >= min, "slippage");
    }

    // Assumes one of the balances is near 0; use _addMaxLiquidity otherwise.
    function _swapAndAddLiquidity(uint256 balance0, uint256 balance1)
        internal
        returns (uint256 amount0, uint256 amount1, uint128 liquidity)
    {
        (bool zeroForOne, uint256 amountIn) = getLiquidityAditionSwapParams(balance0, balance1);
        uint256 amountOut = _swap(zeroForOne, amountIn, 0);
        if (zeroForOne) {
            return _addLiquidity(balance0 - amountIn, balance1 + amountOut, 0);
        } else {
            return _addLiquidity(balance0 + amountOut, balance1 - amountIn, 0);
        }
    }

    function _getLiquidityForAmount0(uint256 amount) internal view returns (uint128 liquidity) {
        (uint160 sqrtPriceX96,,,,,,) = _pool.slot0();
        uint160 sqrtRatioBX96 = UniV3Math.getSqrtRatioAtTick(_tickUpper);
        liquidity = LiquidityAmounts.getLiquidityForAmount0(sqrtPriceX96, sqrtRatioBX96, amount);
    }

    function _getLiquidityForAmount1(uint256 amount) internal view returns (uint128 liquidity) {
        (uint160 sqrtPriceX96,,,,,,) = _pool.slot0();
        uint160 sqrtRatioAX96 = UniV3Math.getSqrtRatioAtTick(_tickLower);
        liquidity = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, sqrtPriceX96, amount);
    }

    function _getLiquidityForAmounts(int24 a, int24 b, uint256 amount0, uint256 amount1)
        internal
        view
        returns (uint128 liquidity)
    {
        (uint160 sqrtPriceX96,,,,,,) = _pool.slot0();
        uint160 sqrtRatioAX96 = UniV3Math.getSqrtRatioAtTick(a);
        uint160 sqrtRatioBX96 = UniV3Math.getSqrtRatioAtTick(b);
        liquidity =
            LiquidityAmounts.getLiquidityForAmounts(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, amount0, amount1);
    }

    function _getAmountsForLiquidity(int24 a, int24 b, uint128 liquidity)
        internal
        view
        returns (uint256 amount0, uint256 amount1)
    {
        (uint160 sqrtPriceX96,,,,,,) = _pool.slot0();
        uint160 sqrtRatioAX96 = UniV3Math.getSqrtRatioAtTick(a);
        uint160 sqrtRatioBX96 = UniV3Math.getSqrtRatioAtTick(b);
        (amount0, amount1) =
            LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, liquidity);
    }

    function diff(int24 a, int24 b) internal pure returns (uint24) {
        if (a < b) return diff(b, a);
        if (a > 0 && b < 0) return uint24(a) + uint24(-b);
        return uint24(a - b);
    }
}

