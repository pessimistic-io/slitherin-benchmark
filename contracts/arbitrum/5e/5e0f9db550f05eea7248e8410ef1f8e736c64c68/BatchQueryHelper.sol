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

    struct PoolVars {
        uint128 liquidity;
        TicketVars[] tickets;
    }

    struct TicketVars {
        int128 liquidityNet;
        int24 tick;
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

    function getV3Tickets(IUniswapV3Pool[] calldata pairs, uint16[] calldata spacings, int24[] calldata minTickets, int24[] calldata maxTickets) external view returns (PoolVars[] memory results){
        uint length = pairs.length;
        require(minTickets.length == length && maxTickets.length == length && spacings.length == length, "length error");
        results = new PoolVars[](length);
        for (uint i = 0; i < length; i++) {
            PoolVars memory item;
            IUniswapV3Pool pair = pairs[i];
            item.liquidity = pair.liquidity();
            uint ticketsLength = (uint256)(maxTickets[i] - minTickets[i])/spacings[i];
            TicketVars[] memory tickets = new TicketVars[](ticketsLength);
            for(uint j = 0; j < ticketsLength; j++){
                TicketVars memory t;
                t.tick = minTickets[i] + (int24)(j * spacings[i]);
                t.liquidityNet = pair.ticks(t.tick);
                tickets[j] = t;
            }
            item.tickets = tickets;
            results[i] = item;
        }
        return results;
    }

    function getV3CurTickets(IUniswapV3Pool[] calldata pairs) external view returns (int24[] memory results){
        results = new int24[](pairs.length);
        for (uint i = 0; i < pairs.length; i++) {
            results[i] = pairs[i].slot0();
        }
        return results;
    }

}

interface IOPBorrowing {
    function twaLiquidity(uint16 marketId) external view returns (uint token0Liq, uint token1Liq);
}

interface IUniswapV3Pool {
    function liquidity() external view returns (uint128);
    function ticks(int24) external view returns (int128 liquidityNet);
    function slot0() external view returns (int24 tick);
}
