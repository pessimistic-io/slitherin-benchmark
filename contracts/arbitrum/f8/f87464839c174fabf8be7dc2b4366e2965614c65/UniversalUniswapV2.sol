//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IPair } from "./IPair.sol";
import { LibAsset } from "./LibAsset.sol";
import { NewUniswapV2Lib } from "./NewUniswapV2Lib.sol";

contract UniversalUniswapV2{
    uint256 constant FEE_OFFSET = 161;
    uint256 constant DIRECTION_FLAG = 0x0000000000000000000000010000000000000000000000000000000000000000;

    struct UniswapV2Data {
        uint256[] pools;
    }

    function swapOnUniversalUniswapV2(
        address fromToken,
        uint256 fromAmount,
        bytes memory payload
    ) internal { 
        UniswapV2Data memory data = abi.decode(payload, (UniswapV2Data));
        _swapOnswapOnUniversalUniswapV2(fromToken, fromAmount, data.pools);
    }

    function _swapOnswapOnUniversalUniswapV2(
        address fromToken,
        uint256 fromAmount,
        uint256[] memory pools
    ) private returns (uint256 tokensBought) {
        uint256 pairs = pools.length;
        require(pairs != 0, "At least one pool required");

        LibAsset.transferAsset(fromToken, payable(address(uint160(pools[0]))), fromAmount);
        tokensBought = fromAmount;

        for (uint256 i = 0; i < pairs; ++i) {
            uint256 p = pools[i];
            address pool = address(uint160(p));
            bool direction = p & DIRECTION_FLAG == 0;
            
            address tokenIn = direction ? IPair(pool).token0() : IPair(pool).token1();
            tokensBought = getAmountOut(
                pool,
                tokenIn,
                tokensBought,
                direction,
                p
            );
            (uint256 amount0Out, uint256 amount1Out) = direction
                ? (uint256(0), tokensBought)
                : (tokensBought, uint256(0));
            IPair(pool).swap(
                amount0Out,
                amount1Out,
                i + 1 == pairs ? address(this) : address(uint160(pools[i + 1])),
                ""
            );
        }
    }

    function getAmountOut(
        address pool,
        address tokenIn,
        uint256 amountIn,
        bool direction,
        uint256 p
    ) internal returns (uint256 tokensBought) {
        (bool success, bytes memory result) = pool.call(abi.encodeWithSelector(IPair.getAmountOut.selector, amountIn, tokenIn));
        if (success) {
            tokensBought = abi.decode(result, (uint256));
        } else {
            tokensBought = tokensBought = NewUniswapV2Lib.getAmountOut(
                amountIn, pool, direction, p >> FEE_OFFSET
            );
        }
    }

    function quoteOnUniversalUniswapV2(
        address fromToken,
        uint256 fromAmount,
        bytes memory payload
    ) internal returns(uint256){ 
        UniswapV2Data memory data = abi.decode(payload, (UniswapV2Data));
       return _quoteOnswapOnUniversalUniswapV2(fromToken, fromAmount, data.pools);
    }

    function _quoteOnswapOnUniversalUniswapV2(
        address fromToken,
        uint256 fromAmount,
        uint256[] memory pools
    ) private returns (uint256 tokensBought) {
        uint256 pairs = pools.length;
        require(pairs != 0, "At least one pool required");

        // LibAsset.transferAsset(fromToken, payable(address(uint160(pools[0]))), fromAmount);
        tokensBought = fromAmount;

        for (uint256 i = 0; i < pairs; ++i) {
            uint256 p = pools[i];
            address pool = address(uint160(p));
            bool direction = p & DIRECTION_FLAG == 0;
            
            address tokenIn = direction ? IPair(pool).token0() : IPair(pool).token1();
            tokensBought = getAmountOut(
                pool,
                tokenIn,
                tokensBought,
                direction,
                p
            );
        }
    }
}
