// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "./BaseUniswapV3Strategy.sol";
import "./BaseAaveStrategy.sol";
import "./BaseHedgedConcentratedLiquidityStrategy.sol";

/// @author YLDR <admin@apyflow.com>
contract UniswapV3AaveStrategy is BaseUniswapV3Strategy, BaseAaveStrategy, BaseHedgedConcentratedLiquidityStrategy {
    struct ConstructorParams {
        // BaseLendingStrategy
        IERC20Metadata collateral;
        IERC20Metadata tokenToBorrow;
        // BaseAaveStrategy
        IAavePool aavePool;
        // BaseHedgedConcentratedLiquidityStrategy
        uint24 initialLTV;
        int24 rehedgeStep;
        // BaseUniswapV3Strategy
        IUniswapV3Pool pool;
        INonfungiblePositionManager positionManager;
        // BaseConcentratedLiquidityStrategy
        int24 ticksDown;
        int24 ticksUp;
        uint24 allowedPoolOracleDeviation;
        ChainlinkPriceFeedAggregator pricesOracle;
        IAssetConverter assetConverter;
        // ApyFlowVault
        IERC20Metadata asset;
        // ERC20
        string name;
        string symbol;
    }

    constructor(ConstructorParams memory params)
        BaseUniswapV3Strategy(params.pool, params.positionManager)
        BaseConcentratedLiquidityStrategy(
            params.ticksDown,
            params.ticksUp,
            params.allowedPoolOracleDeviation,
            params.pricesOracle,
            params.assetConverter
        )
        BaseAaveStrategy(params.aavePool)
        BaseLendingStrategy(params.collateral, params.tokenToBorrow)
        BaseHedgedConcentratedLiquidityStrategy(params.initialLTV, params.rehedgeStep)
        ApyFlowVault(params.asset)
        ERC20(params.name, params.symbol)
    {
        BaseConcentratedLiquidityStrategy._performApprovals();
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

    function _readdLiquidity()
        internal
        virtual
        override(BaseConcentratedLiquidityStrategy, BaseHedgedConcentratedLiquidityStrategy)
    {
        BaseHedgedConcentratedLiquidityStrategy._readdLiquidity();
    }

    function _mintNewPosition(uint256 amount0, uint256 amount1)
        internal
        virtual
        override(BaseConcentratedLiquidityStrategy, BaseHedgedConcentratedLiquidityStrategy)
    {
        BaseHedgedConcentratedLiquidityStrategy._mintNewPosition(amount0, amount1);
    }
}

