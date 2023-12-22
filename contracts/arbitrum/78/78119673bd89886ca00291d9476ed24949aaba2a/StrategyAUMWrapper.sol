//SPDX-License-Identifier: BSL
pragma solidity ^0.7.6;
pragma abicoder v2;

// interfaces
import "./IERC20.sol";
import "./IPancakeV3Pool.sol";

//libraries
import "./LiquidityAmounts.sol";
import "./PositionKey.sol";
import "./TickMath.sol";

interface IDefiEdgeStrategy {
    struct Tick {
        int24 tickLower;
        int24 tickUpper;
    }

    function getTicks() external view returns (Tick[] memory);

    function pool() external view returns (IPancakeV3Pool);
}

contract StrategyAUMWrapper {

    /**
     * @notice Calculate strategy AUM (unused balances + deployed liquidity), unclaimed fees are not included
     * @param _strategy Defiedge strategy contract instance
     * @return reserve0 token0 amount in strategy
     * @return reserve1 token1 amount in strategy
     */
    function getAUMWithoutFees(address _strategy) public view returns(uint256 reserve0, uint256 reserve1){

        IDefiEdgeStrategy strategy = IDefiEdgeStrategy(_strategy);
        IPancakeV3Pool pool = IPancakeV3Pool(strategy.pool());
        // query all ticks from strategy
        IDefiEdgeStrategy.Tick[] memory ticks = strategy.getTicks();

        // get unused amounts
        reserve0 = IERC20(pool.token0()).balanceOf(_strategy);
        reserve1 = IERC20(pool.token1()).balanceOf(_strategy);

        // get AUM from each tick
        for (uint256 i = 0; i < ticks.length; i++) {
            IDefiEdgeStrategy.Tick memory _currTick = ticks[i];

            // get current liquidity from the pool
            (uint128 currentLiquidity, , , , ) = pool.positions(PositionKey.compute(_strategy, _currTick.tickLower, _currTick.tickUpper));

            if (currentLiquidity > 0) {
                // calculate current positions in the pool from currentLiquidity
                (uint256 position0, uint256 position1) = _getAmountsForLiquidity(
                    pool,
                    _currTick.tickLower,
                    _currTick.tickUpper,
                    currentLiquidity
                );

                reserve0 += position0;
                reserve1 += position1;
            }
        }

    }

    /**
     * @notice Calculates the liquidity amount using current ranges
     * @param _pool Instance of the pool
     * @param _tickLower Lower tick
     * @param _tickUpper Upper tick
     * @param _liquidity Liquidity of the pool
     */
    function _getAmountsForLiquidity(
        IPancakeV3Pool _pool,
        int24 _tickLower,
        int24 _tickUpper,
        uint128 _liquidity
    ) internal view returns (uint256 amount0, uint256 amount1) {
        // get sqrtRatios required to calculate liquidity
        (uint160 sqrtRatioX96, , , , , , ) = _pool.slot0();

        // calculate liquidity needs to be added
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(_tickLower),
            TickMath.getSqrtRatioAtTick(_tickUpper),
            _liquidity
        );
    }

}
