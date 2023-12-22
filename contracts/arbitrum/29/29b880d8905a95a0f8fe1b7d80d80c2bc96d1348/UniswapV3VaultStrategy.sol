// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import "./IUniswapV3Pool.sol";

import "./SqrtPriceMath.sol";
import "./TickMath.sol";

import "./IUniswapV3VaultStrategy.sol";
import "./INonfungiblePositionManager.sol";
import "./LiquidityAmounts.sol";

import "./ITokenToUsdcOracle.sol";

contract UniswapV3VaultStrategy is IUniswapV3VaultStrategy {
    address token0Address;
    address token1Address;
    ITokenToUsdcOracle token0Oracle;
    ITokenToUsdcOracle token1Oracle;
    IUniswapV3Pool pool;
    INonfungiblePositionManager positionManager;

    constructor(IUniswapV3Pool _pool, INonfungiblePositionManager _positionManager, address _token0, address _token1, address _token0Oracle, address _token1Oracle) {
        token0Address = _token0;
        token1Address = _token1;
        token0Oracle = ITokenToUsdcOracle(_token0Oracle);
        token1Oracle = ITokenToUsdcOracle(_token1Oracle);
        pool = _pool;
        positionManager = _positionManager;
    }

    function getBalance(address strategist) override external view returns(uint256 amount) {
        (uint token0Balance, uint token1Balance) = _getTokensBalance(strategist);

        uint token0UsdcBalance = token0Oracle.usdcAmount(token0Balance);
        uint token1UsdcBalance = token1Oracle.usdcAmount(token1Balance);
        amount = token0UsdcBalance + token1UsdcBalance;

        return amount;
    }

    function _getTokensBalance(address strategist) private view returns (uint token0Balance, uint token1Balance) {
        uint balance = positionManager.balanceOf(strategist);

        uint[] memory k = new uint[](balance);

        for (uint i = 0; i < balance; i++) {
            uint tokenId = positionManager.tokenOfOwnerByIndex(strategist, i);
            (
            uint96 nonce,
            ,
            address token0,
            address token1,
            ,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,
            ) = positionManager.positions(tokenId);

            if (token0 == token0Address && token1 == token1Address) {
                (uint amount0, uint amount1) = processLiquidity(tickLower, tickUpper, liquidity);
                token0Balance += amount0;
                token1Balance += amount1;
            }
        }

        return (token0Balance, token1Balance);
    }

    function processLiquidity(int24 _tickLower, int24 _tickUpper, uint128 _liquidity) private view returns(uint256 amount0, uint256 amount1) {
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();

        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(_tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(_tickUpper);

        return LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, _liquidity);
    }
}
