// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "./LiquidityAmounts.sol";
import "./TickMath.sol";
import "./HarvestableApyFlowVault.sol";
import "./Utils.sol";
import "./SafeAssetConverter.sol";
import "./PricesLibrary.sol";
import "./ChainlinkPriceFeedAggregator.sol";
import "./ConcentratedLiquidityLibrary.sol";
import {Math} from "./Math.sol";

abstract contract BaseConcentratedLiquidityStrategy is HarvestableApyFlowVault {
    using SafeERC20 for IERC20;
    using SafeAssetConverter for IAssetConverter;
    using PricesLibrary for ChainlinkPriceFeedAggregator;

    error PoolPriceDeviationTooHigh(int24 oracleTick, int24 poolTick, uint24 diff, uint24 allowed);

    event LiquidityReadded(int24 tick);

    struct PositionState {
        int24 tickLower;
        int24 tickUpper;
        uint160 sqrtPriceX96;
        uint128 liquidity;
    }

    event ConcentratedLiquidityCheckpoint(PositionState state);

    struct PositionData {
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
    }

    ChainlinkPriceFeedAggregator public immutable pricesOracle;
    IAssetConverter public immutable assetConverter;
    int24 public immutable ticksDown;
    int24 public immutable ticksUp;
    uint24 public immutable allowedPoolOracleDeviation;

    constructor(
        int24 _ticksDown,
        int24 _ticksUp,
        uint24 _allowedPoolOracleDeviation,
        ChainlinkPriceFeedAggregator _pricesOracle,
        IAssetConverter _assetConverter
    ) {
        pricesOracle = _pricesOracle;
        assetConverter = _assetConverter;
        allowedPoolOracleDeviation = _allowedPoolOracleDeviation;
        ticksDown = _ticksDown;
        ticksUp = _ticksUp;
    }

    function token0() public view virtual returns (address);

    function token1() public view virtual returns (address);

    function _isPositionExists() internal view virtual returns (bool);

    function _increaseLiquidity(uint256 amount0, uint256 amount1) internal virtual;

    function _decreaseLiquidity(uint128 liquidity) internal virtual returns (uint256 amount0, uint256 amount1);

    function _mint(int24 tickLower, int24 tickUpper, uint256 amount0, uint256 amount1) internal virtual;

    function getPoolData() public view virtual returns (int24 currentTick, uint160 sqrtPriceX96);

    function getPositionData() public view virtual returns (PositionData memory data);

    function _collectAllAndBurn() internal virtual;

    function _collect() internal virtual;

    function _tickSpacing() internal view virtual returns (int24);

    function getConcentratedLiquidityState() public view returns (PositionState memory state) {
        if (!_isPositionExists()) {
            return state;
        }
        (state.tickLower, state.tickUpper) = _getTicks();
        (, state.sqrtPriceX96) = getPoolData();
        state.liquidity = getPositionData().liquidity;
    }

    function _emitConcentratedLiquidityCheckpoint() internal {
        emit ConcentratedLiquidityCheckpoint(getConcentratedLiquidityState());
    }

    modifier checkpointConcentratedLiquidity() {
        _emitConcentratedLiquidityCheckpoint();
        _;
        _emitConcentratedLiquidityCheckpoint();
    }

    function _checkDeviation() internal view {
        (int24 oracleTick,) = getPoolStateFromOracle();
        (int24 poolTick,) = getPoolData();
        uint24 diff = oracleTick < poolTick ? uint24(poolTick - oracleTick) : uint24(oracleTick - poolTick);

        if (diff > allowedPoolOracleDeviation) {
            revert PoolPriceDeviationTooHigh(oracleTick, poolTick, diff, allowedPoolOracleDeviation);
        }
    }

    modifier checkDeviation() {
        _checkDeviation();
        _;
    }

    function _performApprovals() internal virtual {
        Utils.approveIfZeroAllowance(asset(), address(assetConverter));
        Utils.approveIfZeroAllowance(token0(), address(assetConverter));
        Utils.approveIfZeroAllowance(token1(), address(assetConverter));
    }

    function _getTicks() internal view returns (int24 tickLower, int24 tickUpper) {
        if (_isPositionExists()) {
            PositionData memory data = getPositionData();
            tickLower = data.tickLower;
            tickUpper = data.tickUpper;
        } else {
            (int24 currentTick,) = getPoolData();
            tickLower = currentTick - ticksDown;
            tickUpper = currentTick + ticksUp;
            int24 spacing = _tickSpacing();
            tickLower = (tickLower / spacing) * spacing;
            tickUpper = (tickUpper / spacing) * spacing;
        }
    }

    function _getSqrtPrices()
        internal
        view
        returns (uint160 sqrtPriceAX96, uint160 sqrtPriceX96, uint160 sqrtPriceBX96)
    {
        (int24 tickLower, int24 tickUpper) = _getTicks();
        sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        (, sqrtPriceX96) = getPoolData();
        sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
    }

    function _mintNewPosition(uint256 amount0, uint256 amount1) internal virtual {
        (int24 tickLower, int24 tickUpper) = _getTicks();
        (, uint160 sqrtPriceX96) = getPoolData();
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            TickMath.getSqrtRatioAtTick(tickLower),
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(tickUpper),
            amount0,
            amount1
        );
        if (liquidity == 0) {
            return;
        }
        _mint(tickLower, tickUpper, amount0, amount1);
    }

    function _increaseLiquidityOrMintPosition(uint256 amount0, uint256 amount1) internal {
        (uint160 sqrtPriceAX96, uint160 sqrtPriceX96, uint160 sqrtPriceBX96) = _getSqrtPrices();
        uint128 liquidity =
            LiquidityAmounts.getLiquidityForAmounts(sqrtPriceAX96, sqrtPriceX96, sqrtPriceBX96, amount0, amount1);
        if (liquidity == 0) {
            return;
        }
        if (!_isPositionExists()) {
            _mintNewPosition(amount0, amount1);
        } else {
            _increaseLiquidity(amount0, amount1);
        }
    }

    function _totalAssets() internal view virtual override returns (uint256 assets) {
        if (!_isPositionExists()) {
            return 0;
        }
        (uint160 sqrtPriceAX96, uint160 sqrtPriceX96, uint160 sqrtPriceBX96) = _getSqrtPrices();
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, getPositionData().liquidity
        );
        uint256 valueInUSD;
        valueInUSD += pricesOracle.convertToUSD(token0(), amount0);
        valueInUSD += pricesOracle.convertToUSD(token1(), amount1);
        assets = pricesOracle.convertFromUSD(valueInUSD, asset());
    }

    function _getAmounts(uint256 assets) internal view returns (uint256 amountFor0, uint256 amountFor1) {
        (uint160 sqrtPriceAX96, uint160 sqrtPriceX96, uint160 sqrtPriceBX96) = _getSqrtPrices();
        (amountFor0, amountFor1) = ConcentratedLiquidityLibrary.getAmountsForLiquidityProviding(
            sqrtPriceAX96, sqrtPriceX96, sqrtPriceBX96, assets
        );
    }

    function _deposit(uint256 assets) internal virtual override checkDeviation checkpointConcentratedLiquidity {
        (uint256 amountFor0, uint256 amountFor1) = _getAmounts(assets);
        uint256 amount0 = assetConverter.safeSwap(asset(), token0(), amountFor0);
        uint256 amount1 = assetConverter.safeSwap(asset(), token1(), amountFor1);
        _increaseLiquidityOrMintPosition(amount0, amount1);
        assetConverter.safeSwap(token0(), asset(), IERC20(token0()).balanceOf(address(this)));
        assetConverter.safeSwap(token1(), asset(), IERC20(token1()).balanceOf(address(this)));
    }

    function _redeem(uint256 shares)
        internal
        virtual
        override
        checkDeviation
        checkpointConcentratedLiquidity
        returns (uint256 assets)
    {
        uint128 liquidity = uint128((getPositionData().liquidity * shares) / totalSupply());

        (uint256 amount0, uint256 amount1) = _decreaseLiquidity(liquidity);

        _collect();

        if (getPositionData().liquidity == 0) {
            _collectAllAndBurn();
        }

        assets += assetConverter.safeSwap(token0(), asset(), amount0);
        assets += assetConverter.safeSwap(token1(), asset(), amount1);
    }

    function _readdLiquidity() internal virtual {
        // 1. Withdraw all liquidity
        _decreaseLiquidity(getPositionData().liquidity);
        _collectAllAndBurn();

        // 2. Deal with leftovers in vault asset first
        uint256 amountFor0;
        uint256 amountFor1;
        if ((asset() != token0()) && (asset() != token1())) {
            uint256 assetAmount = IERC20(asset()).balanceOf(address(this));
            (amountFor0, amountFor1) = _getAmounts(assetAmount);
            assetConverter.safeSwap(asset(), token0(), amountFor0);
            assetConverter.safeSwap(asset(), token1(), amountFor1);
        }

        // 3. Capture amounts
        uint256 amount0 = IERC20(token0()).balanceOf(address(this));
        uint256 amount1 = IERC20(token1()).balanceOf(address(this));

        // 4. Calculate target amounts
        uint256 amountInUSD =
            pricesOracle.convertToUSD(token0(), amount0) + pricesOracle.convertToUSD(token1(), amount1);
        (amountFor0, amountFor1) = _getAmounts(amountInUSD);

        uint256 targetAmount0 = pricesOracle.convertFromUSD(amountFor0, token0());
        uint256 targetAmount1 = pricesOracle.convertFromUSD(amountFor1, token1());

        // 5. Swap to match target state
        if (amount0 > targetAmount0) {
            amount1 += assetConverter.safeSwap(token0(), token1(), amount0 - targetAmount0);
            amount0 = targetAmount0;
        } else if (amount1 > targetAmount1) {
            amount0 += assetConverter.safeSwap(token1(), token0(), amount1 - targetAmount1);
            amount1 = targetAmount1;
        }

        // 6. Mint position
        _mintNewPosition(amount0, amount1);

        // 7. Swap leftovers
        assetConverter.safeSwap(token0(), asset(), IERC20(token0()).balanceOf(address(this)));
        assetConverter.safeSwap(token1(), asset(), IERC20(token1()).balanceOf(address(this)));
    }

    /// @dev We could have overriden _harvest function in other contracts, but this would make inheritance way too complex
    function _processAdditionalRewards() internal virtual;

    function _harvest() internal virtual override {
        if (!_isPositionExists()) return;
        _collect();
        assetConverter.safeSwap(token0(), asset(), IERC20(token0()).balanceOf(address(this)));
        assetConverter.safeSwap(token1(), asset(), IERC20(token1()).balanceOf(address(this)));

        _processAdditionalRewards();
    }

    function getPoolStateFromOracle() public view returns (int24 tick, uint160 sqrtPriceX96) {
        uint256 token0Rate = pricesOracle.getRate(token0());
        uint256 token1Rate = pricesOracle.getRate(token1());

        // price = (10 ** token1Decimals) * token0Rate / ((10 ** token0Decimals) * token1Rate)
        // sqrtPriceX96 = sqrt(price * 2^192)

        // overflows only if token0 is 2**160 times more expensive than token1 (considered non-likely)
        uint256 factor1 = Math.mulDiv(token0Rate, 2 ** 96, token1Rate);

        // Cannot overflow if token1Decimals <= 18 and token0Decimals <= 18
        uint256 factor2 =
            Math.mulDiv(10 ** IERC20Metadata(token1()).decimals(), 2 ** 96, 10 ** IERC20Metadata(token0()).decimals());

        uint128 factor1Sqrt = uint128(Math.sqrt(factor1));
        uint128 factor2Sqrt = uint128(Math.sqrt(factor2));

        sqrtPriceX96 = factor1Sqrt * factor2Sqrt;
        tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
    }

    function _isInRange(uint160 sqrtPriceAX96, uint160 sqrtPriceX96, uint160 sqrtPriceBX96)
        private
        pure
        returns (bool)
    {
        return (sqrtPriceX96 >= sqrtPriceAX96) && (sqrtPriceX96 < sqrtPriceBX96);
    }

    function readdLiquidity() public virtual checkpointConcentratedLiquidity checkpointLeftovers {
        bool calledByOwner = msg.sender == owner();

        if (!calledByOwner) {
            _checkDeviation();
        }

        _harvest(false);

        (, uint160 oracleSqrtPriceX96) = getPoolStateFromOracle();
        (int24 poolTick, uint160 poolSqrtPriceX96) = getPoolData();

        PositionData memory data = getPositionData();

        uint160 sqrtPriceLowerX96 = TickMath.getSqrtRatioAtTick(data.tickLower);
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtRatioAtTick(data.tickUpper);

        // bool isInRebalanceRange = !_isInRange(sqrtPriceLowerX96, poolSqrtPriceX96, sqrtPriceUpperX96)
        //     && !_isInRange(sqrtPriceLowerX96, oracleSqrtPriceX96, sqrtPriceUpperX96);
        bool isInRebalanceRange = !_isInRange(sqrtPriceLowerX96, poolSqrtPriceX96, sqrtPriceUpperX96);

        _readdLiquidity();

        if (!calledByOwner) {
            require(isInRebalanceRange);
        }

        emit LiquidityReadded(poolTick);
    }
}

