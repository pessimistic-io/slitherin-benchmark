// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {SafeERC20} from "./SafeERC20.sol";
import {Math} from "./Math.sol";
import {IERC20} from "./ERC20_IERC20.sol";
import {ConcentratedLiquidityLibrary} from "./ConcentratedLiquidityLibrary.sol";
import {ChainlinkPriceFeedAggregator, PricesLibrary} from "./PricesLibrary.sol";
import {IAssetConverter, SafeAssetConverter} from "./SafeAssetConverter.sol";
import {BaseConcentratedLiquidityStrategy} from "./BaseConcentratedLiquidityStrategy.sol";
import {BaseLendingStrategy} from "./BaseLendingStrategy.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";

/// @dev This contract assumes that tokenToBorrow token is one of two
/// pool tokens and that asset() == collateral is correlated with other pool token
/// (usually stablecoin)
abstract contract BaseHedgedConcentratedLiquidityStrategy is BaseConcentratedLiquidityStrategy, BaseLendingStrategy {
    using SafeERC20 for IERC20;
    using SafeAssetConverter for IAssetConverter;
    using PricesLibrary for ChainlinkPriceFeedAggregator;

    event Rehedged(int24 tick);

    uint24 public initialLTV;
    address private immutable stablePoolToken;
    int24 public immutable rehedgeStep;
    int24 public lastRehedgeTick;

    constructor(uint24 _initialLTV, int24 _rehedgeStep) {
        require(asset() == address(collateral), "Invalid configuration");
        require((token0() == address(tokenToBorrow)) || (token1() == address(tokenToBorrow)), "Invalid configuration");

        initialLTV = _initialLTV;
        rehedgeStep = _rehedgeStep;

        stablePoolToken = (token0() == address(tokenToBorrow)) ? token1() : token0();
    }

    function updateInitialLTV(uint24 newLTV) external onlyOwner {
        initialLTV = newLTV;
    }

    function _totalAssets() internal view virtual override returns (uint256 assets) {
        BaseLendingStrategy.LendingPositionState memory lendingState = getLendingPositionState();

        assets = BaseConcentratedLiquidityStrategy._totalAssets();
        uint256 valueInUSD = pricesOracle.convertToUSD(asset(), assets);
        valueInUSD += pricesOracle.convertToUSD(address(collateral), lendingState.collateral);
        valueInUSD -= pricesOracle.convertToUSD(address(tokenToBorrow), lendingState.debt);
        assets = pricesOracle.convertFromUSD(valueInUSD, asset());
    }

    /// @dev function which calculates how funds should be distributed
    /// @param assets amount of assets to be distributed (in vault asset aka collateral)
    /// @return amountToSupply amount of assets to be supplied to the lending protocol
    /// @return amountToBorrow amount of borrow token to be borrowed from the lending protocol
    /// @return amountFor0 amount of asset to be swapped into token0
    /// @return amountFor1 amount of asset to be swapped into token1
    /// @return extraDebt amount of debt tokens that has to be swapped into stable pool token
    function _getAmountsHedged(uint256 assets)
        internal
        returns (
            uint256 amountToSupply,
            uint256 amountToBorrow,
            uint256 amountFor0,
            uint256 amountFor1,
            uint256 extraDebt
        )
    {
        uint256 ltv;
        if (!_isPositionExists()) {
            ltv = initialLTV;

            (amountFor0, amountFor1) = _getAmounts(assets);
            (uint256 amountForDebt, uint256 amountForCollateral) =
                (token0() == address(tokenToBorrow)) ? (amountFor0, amountFor1) : (amountFor1, amountFor0);

            uint256 denominator = amountForDebt + (ltv * amountForCollateral) / (10 ** 6);
            uint256 delta = (denominator == 0)
                ? 0
                : Math.mulDiv(amountForDebt - (ltv * amountForDebt) / (10 ** 6), amountForCollateral, denominator);
            amountToSupply = amountForDebt + delta;
            amountForDebt = 0;
            amountForCollateral -= delta;
            (amountFor0, amountFor1) = (token0() == address(tokenToBorrow))
                ? (amountForDebt, amountForCollateral)
                : (amountForCollateral, amountForDebt);
        } else {
            ltv = _getCurrentLTV();
            amountToSupply = (_getCurrentCollateral() * assets) / _totalAssets();
            // exclude assets locked as collateral: (1 - ltv) * collateral
            assets -= Math.mulDiv(amountToSupply, (10 ** 6) - ltv, (10 ** 6), Math.Rounding.Up);
            uint256 assetsInDebt = amountToSupply * ltv / (10 ** 6);
            (amountFor0, amountFor1) = _getAmounts(assets);
            (uint256 amountForDebt, uint256 amountForCollateral) =
                (token0() == address(tokenToBorrow)) ? (amountFor0, amountFor1) : (amountFor1, amountFor0);
            if (amountForDebt >= assetsInDebt) {
                amountForDebt -= assetsInDebt;
            } else {
                uint256 extraDebtAssets = assetsInDebt - amountForDebt;
                amountForCollateral -= extraDebtAssets;
                extraDebt = pricesOracle.convert(asset(), address(tokenToBorrow), extraDebtAssets);
                amountForDebt = 0;
            }
            (amountFor0, amountFor1) = (token0() == address(tokenToBorrow))
                ? (amountForDebt, amountForCollateral)
                : (amountForCollateral, amountForDebt);
        }
        amountToBorrow = _getNeededDebt(amountToSupply, ltv);
    }

    function _deposit(uint256 assets)
        internal
        virtual
        override
        checkDeviation
        checkpointConcentratedLiquidity
        checkpointLendingPosition
    {
        (uint256 amountToSupply, uint256 amountToBorrow, uint256 amountFor0, uint256 amountFor1, uint256 extraDebt) =
            _getAmountsHedged(assets);

        uint256 amount0 = assetConverter.safeSwap(asset(), token0(), amountFor0);
        uint256 amount1 = assetConverter.safeSwap(asset(), token1(), amountFor1);

        (uint256 amountBorrow, uint256 amountStable) =
            (token0() == address(tokenToBorrow)) ? (amount0, amount1) : (amount1, amount0);

        _supply(amountToSupply);
        _borrow(amountToBorrow);

        amountBorrow += amountToBorrow - extraDebt;
        amountStable += assetConverter.safeSwap(address(tokenToBorrow), stablePoolToken, extraDebt);

        (amount0, amount1) =
            (token0() == address(tokenToBorrow)) ? (amountBorrow, amountStable) : (amountStable, amountBorrow);

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
        checkpointLendingPosition
        returns (uint256 assets)
    {
        uint128 liquidity = uint128((getPositionData().liquidity * shares) / totalSupply());

        (uint256 amount0, uint256 amount1) = (liquidity > 0) ? _decreaseLiquidity(liquidity) : (0, 0);
        _collect();

        if (getPositionData().liquidity == 0) {
            _collectAllAndBurn();
        }

        uint256 debtToRepay = (_getCurrentDebt() * shares) / totalSupply();

        (uint256 tokenToBorrowAmount, uint256 stablePoolTokenAmount) =
            (token0() == address(tokenToBorrow)) ? (amount0, amount1) : (amount1, amount0);

        if (tokenToBorrowAmount < debtToRepay) {
            uint256 amountToSwap =
                pricesOracle.convert(address(tokenToBorrow), stablePoolToken, debtToRepay - tokenToBorrowAmount);
            amountToSwap = Math.min(amountToSwap, stablePoolTokenAmount);
            tokenToBorrowAmount += assetConverter.safeSwap(stablePoolToken, address(tokenToBorrow), amountToSwap);
            stablePoolTokenAmount -= amountToSwap;
            debtToRepay = Math.min(debtToRepay, tokenToBorrowAmount);
        }
        tokenToBorrowAmount -= debtToRepay;

        assets = _repayAndWithdrawProportionally(debtToRepay);
        assets += assetConverter.safeSwap(address(tokenToBorrow), asset(), tokenToBorrowAmount);
        assets += assetConverter.safeSwap(stablePoolToken, asset(), stablePoolTokenAmount);
    }

    function _mintNewPosition(uint256 amount0, uint256 amount1) internal virtual override {
        super._mintNewPosition(amount0, amount1);
        (lastRehedgeTick,) = getPoolData();
    }

    function _readdLiquidity() internal virtual override checkpointLendingPosition {
        // 1. Withdraw all liquidity
        _decreaseLiquidity(getPositionData().liquidity);
        _collectAllAndBurn();

        // At this point we may have non-zero borrow token balance,
        // non-zero collateral (asset) balance and non-zero pool stable token balance

        // 2. Swap stable pool token to asset (collateral)
        assetConverter.safeSwap(stablePoolToken, asset(), IERC20(stablePoolToken).balanceOf(address(this)));

        // At this point we only have collateral (asset) and borrow token balances

        // 3. Get current state
        uint256 currentCollateral = _getCurrentCollateral();
        uint256 currentDebt = _getCurrentDebt();
        uint256 tokenToBorrowBalance = IERC20(address(tokenToBorrow)).balanceOf(address(this));
        uint256 collateralBalance = IERC20(address(collateral)).balanceOf(address(this));

        // 4. Rebalance borrow token balance to match debt
        if (tokenToBorrowBalance > currentDebt) {
            tokenToBorrowBalance = currentDebt;
            collateralBalance +=
                assetConverter.safeSwap(address(tokenToBorrow), address(collateral), tokenToBorrowBalance - currentDebt);
        } else {
            uint256 amountToSwap = Math.min(
                pricesOracle.convert(address(tokenToBorrow), address(collateral), currentDebt - tokenToBorrowBalance),
                collateralBalance
            );
            collateralBalance -= amountToSwap;
            tokenToBorrowBalance += assetConverter.safeSwap(address(collateral), address(tokenToBorrow), amountToSwap);
        }

        // At this point we have borrow token balance which is equal to current debt
        // and some collateral (asset) balance

        // 5. Calculate target state
        uint256 assets = totalAssets();
        assets += pricesOracle.convert(address(tokenToBorrow), address(collateral), tokenToBorrowBalance);
        (uint256 neededCollateral, uint256 neededDebt,,,) = _getAmountsHedged(assets);

        // 6. Calculate steps to reach target state
        uint256 amountToRepay =
            Math.min((currentDebt > neededDebt) ? currentDebt - neededDebt : 0, tokenToBorrowBalance);
        uint256 amountToWithdraw = (currentCollateral > neededCollateral) ? currentCollateral - neededCollateral : 0;
        uint256 amountToBorrow = (neededDebt > currentDebt) ? neededDebt - currentDebt : 0;
        uint256 amountToSupply = Math.min(
            (neededCollateral > currentCollateral) ? neededCollateral - currentCollateral : 0, collateralBalance
        );

        // 7. Execute steps
        _repay(amountToRepay);
        tokenToBorrowBalance -= amountToRepay;
        currentDebt -= amountToRepay;

        _withdraw(amountToWithdraw);
        collateralBalance += amountToWithdraw;
        currentCollateral -= amountToWithdraw;

        _supply(amountToSupply);
        collateralBalance -= amountToSupply;
        currentCollateral += amountToSupply;

        _borrow(amountToBorrow);
        tokenToBorrowBalance += amountToBorrow;
        currentDebt += amountToBorrow;

        // At this point we still have borrow token balance which is equal to current debt

        // 8. Swap all left collateral to stable pool token
        assetConverter.safeSwap(address(collateral), stablePoolToken, collateralBalance);

        uint256 amount0 = IERC20(token0()).balanceOf(address(this));
        uint256 amount1 = IERC20(token1()).balanceOf(address(this));

        _mintNewPosition(amount0, amount1);

        // 9. Swap leftovers back
        assetConverter.safeSwap(token0(), asset(), IERC20(token0()).balanceOf(address(this)));
        assetConverter.safeSwap(token1(), asset(), IERC20(token1()).balanceOf(address(this)));
    }

    function _needRehedge(int24 tick) private view returns (bool) {
        return (tick > (lastRehedgeTick + int24(rehedgeStep))) || (tick < (lastRehedgeTick - int24(rehedgeStep)));
    }

    function rehedge() public checkDeviation checkpointConcentratedLiquidity checkpointLendingPosition {
        (int24 oracleTick,) = getPoolStateFromOracle();
        (int24 poolTick,) = getPoolData();

        // require(_needRehedge(poolTick) && _needRehedge(oracleTick));
        require(_needRehedge(poolTick));

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
}

