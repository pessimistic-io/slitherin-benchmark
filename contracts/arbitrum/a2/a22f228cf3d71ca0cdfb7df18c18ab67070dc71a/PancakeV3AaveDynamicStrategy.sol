// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "./BasePancakeV3Strategy.sol";
import "./BaseAaveStrategy.sol";
import "./BaseDynamicallyHedgedConcentratedLiquidityStrategy.sol";

/// @author YLDR <admin@apyflow.com>
contract PancakeV3AaveDynamicStrategy is
    BasePancakeV3Strategy,
    BaseAaveStrategy,
    BaseDynamicallyHedgedConcentratedLiquidityStrategy
{
    struct ConstructorParams {
        // BaseLendingStrategy
        IERC20Metadata collateral;
        IERC20Metadata tokenToBorrow;
        // BaseAaveStrategy
        IAavePool aavePool;
        // BaseHedgedConcentratedLiquidityStrategy
        uint24 initialLTV;
        // BasePancakeV3Strategy
        IMasterChefV3 farm;
        uint256 pid;
        // BaseConcentratedLiquidityStrategy
        int24 ticksDown;
        int24 ticksUp;
        uint24 allowedPoolOracleDeviation;
        bool readdOnProfit;
        ChainlinkPriceFeedAggregator pricesOracle;
        IAssetConverter assetConverter;
        // BaseDynamicallyHedgedConcentratedLiquidityStrategy
        int24 rehedgeStep;
        // ApyFlowVault
        IERC20Metadata asset;
        // ERC20
        string name;
        string symbol;
    }

    constructor(ConstructorParams memory params)
        BaseConcentratedLiquidityStrategy(
            params.ticksDown,
            params.ticksUp,
            params.allowedPoolOracleDeviation,
            params.readdOnProfit,
            params.pricesOracle,
            params.assetConverter
        )
        BaseHedgedConcentratedLiquidityStrategy(params.initialLTV)
        BaseDynamicallyHedgedConcentratedLiquidityStrategy(params.rehedgeStep)
        BasePancakeV3Strategy(params.farm, params.pid)
        BaseLendingStrategy(params.collateral, params.tokenToBorrow)
        BaseAaveStrategy(params.aavePool)
        ApyFlowVault(params.asset)
        ERC20(params.name, params.symbol)
    {
        BaseConcentratedLiquidityStrategy._performApprovals();
    }

    function _harvest() internal override(BasePancakeV3Strategy, BaseConcentratedLiquidityStrategy) {
        BasePancakeV3Strategy._harvest();
    }

    function _totalAssets()
        internal
        view
        virtual
        override(BaseConcentratedLiquidityStrategy, BaseHedgedConcentratedLiquidityStrategy)
        returns (uint256 assets)
    {
        return BaseHedgedConcentratedLiquidityStrategy._totalAssets();
    }

    function _deposit(uint256 assets)
        internal
        virtual
        override(BaseConcentratedLiquidityStrategy, BaseHedgedConcentratedLiquidityStrategy)
    {
        BaseHedgedConcentratedLiquidityStrategy._deposit(assets);
    }

    function _redeem(uint256 shares)
        internal
        virtual
        override(BaseConcentratedLiquidityStrategy, BaseHedgedConcentratedLiquidityStrategy)
        returns (uint256 assets)
    {
        return BaseHedgedConcentratedLiquidityStrategy._redeem(shares);
    }

    function _mintNewPosition(uint256 amount0, uint256 amount1)
        internal
        virtual
        override(BaseConcentratedLiquidityStrategy, BaseDynamicallyHedgedConcentratedLiquidityStrategy)
    {
        BaseDynamicallyHedgedConcentratedLiquidityStrategy._mintNewPosition(amount0, amount1);
    }

    function _readdLiquidity()
        internal
        virtual
        override(BaseConcentratedLiquidityStrategy, BaseHedgedConcentratedLiquidityStrategy)
    {
        BaseHedgedConcentratedLiquidityStrategy._readdLiquidity();
    }
}

