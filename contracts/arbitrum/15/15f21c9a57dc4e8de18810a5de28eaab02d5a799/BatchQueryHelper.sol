// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "./DexAggregatorInterface.sol";
import "./IERC20.sol";

contract BatchQueryHelper {

    constructor ()
    {
    }

    struct PriceVars {
        uint256 price;
        uint8 decimal;
    }

    struct LiqVars {
        uint256 token0Liq;
        uint256 token1Liq;
        uint256 token0TwaLiq;
        uint256 token1TwaLiq;
    }

    struct V3PoolVars {
        int24 tick;
        int24 tickSpacing;
        uint128 liquidity;
        address token0;
        address token1;
    }

    struct TickVars {
        int128[] liquidityNets;
        int24[] ticks;
    }

    function getPrices(DexAggregatorInterface dexAgg, address[] calldata token0s, address[] calldata token1s, bytes[] calldata dexDatas) external view returns (PriceVars[] memory results){
        results = new PriceVars[](token0s.length);
        for (uint i = 0; i < token0s.length; i++) {
            PriceVars memory item;
            (item.price, item.decimal) = dexAgg.getPrice(token0s[i], token1s[i], dexDatas[i]);
            results[i] = item;
        }
        return results;
    }

    function getLiqs(IOPBorrowing opBorrowing, uint16[] calldata markets, address[] calldata pairs, address[] calldata token0s, address[] calldata token1s) external view returns (LiqVars[] memory results){
        require(markets.length == pairs.length && token0s.length == token1s.length && markets.length == token0s.length, "length error");
        results = new LiqVars[](markets.length);
        for (uint i = 0; i < markets.length; i++) {
            LiqVars memory item;
            item.token0Liq = IERC20(token0s[i]).balanceOf(pairs[i]);
            item.token1Liq = IERC20(token1s[i]).balanceOf(pairs[i]);
            (item.token0TwaLiq, item.token1TwaLiq) = opBorrowing.twaLiquidity(markets[i]);
            results[i] = item;
        }
        return results;
    }

    function getV3Tickets(IUniswapV3Pool[] calldata pairs, int24[] calldata minTickets, int24[] calldata maxTickets) external view returns (TickVars[] memory results){
        uint length = pairs.length;
        require(minTickets.length == length && maxTickets.length == length, "length error");
        results = new TickVars[](length);
        for (uint i = 0; i < length; i++) {
            IUniswapV3Pool pair = pairs[i];
            int24 tickSpacing = pair.tickSpacing();
            int24 ticketsLength = (maxTickets[i] - minTickets[i]) / tickSpacing;
            TickVars memory tickVars;
            int128[] memory liquidityNets = new int128[]((uint)(ticketsLength));
            int24[] memory ticks = new int24[]((uint)(ticketsLength));
            for(int24 j = 0; j < ticketsLength; j++){
                int24 tick = minTickets[i] + j * tickSpacing;
                ticks[(uint)(j)] = tick;
                (,int128 liquidityNet,,,,,,) = pair.ticks(tick);
                liquidityNets[(uint)(j)] = liquidityNet;
            }
            tickVars.ticks = ticks;
            tickVars.liquidityNets = liquidityNets;
            results[i] = tickVars;
        }
    }

    function getV3Pools(IUniswapV3Pool[] calldata pairs) external view returns (V3PoolVars[] memory results){
        results = new V3PoolVars[](pairs.length);
        for (uint i = 0; i < pairs.length; i++) {
            IUniswapV3Pool pair = pairs[i];
            V3PoolVars memory item;
            (,int24 tick,,,,,) = pair.slot0();
            item.tick = tick;
            item.tickSpacing = pair.tickSpacing();
            item.liquidity = pair.liquidity();
            item.token0 = pair.token0();
            item.token1 = pair.token1();
            results[i] = item;
        }
        return results;
    }

}

interface IOPBorrowing {
    function twaLiquidity(uint16 marketId) external view returns (uint token0Liq, uint token1Liq);
}

interface IUniswapV3Pool {
    function liquidity() external view returns (uint128);

    function tickSpacing() external view returns (int24);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function ticks(int24 tick) external view returns (
        uint128 liquidityGross,
        int128 liquidityNet,
        uint256 feeGrowthOutside0X128,
        uint256 feeGrowthOutside1X128,
        int56 tickCumulativeOutside,
        uint160 secondsPerLiquidityOutsideX128,
        uint32 secondsOutside,
        bool initialized
    );

    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    );
}
