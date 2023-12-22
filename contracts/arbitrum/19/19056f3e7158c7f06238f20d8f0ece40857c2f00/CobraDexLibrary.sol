// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

import "./ICobraDexFactory.sol";
import "./ICobraDexPair.sol";

import "./SafeMath.sol";

library CobraDexLibrary {
    using SafeMathUniswap for uint;

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'CobraDexLibrary: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'CobraDexLibrary: ZERO_ADDRESS');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint160(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                ICobraDexFactory(factory).pairCodeHash()
                //hex'99702b0414c415485eea8259f09f00a8cfdacbe606780286f272c79ae3a4d43d ' // init code hash - normal
            )))));
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint reserve0, uint reserve1,) = ICobraDexPair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, 'CobraDexLibrary: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'CobraDexLibrary: INSUFFICIENT_LIQUIDITY');
        amountB = amountA.mul(reserveB) / reserveA;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(address factory, uint amountOut, address token0, address token1, uint64 feeRebate) internal view returns (uint amountIn) {
        (uint reserveIn, uint reserveOut) = getReserves(factory, token0, token1);
        require(amountOut > 0, 'CobraDexLibrary: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'CobraDexLibrary: INSUFFICIENT_LIQUIDITY');

        address pair = pairFor(factory, token0, token1);
        uint FEE_DIVISOR = ICobraDexPair(pair).getFeeDivisor();
        uint fee = ICobraDexPair(pair).calculateFee(feeRebate);
        uint inverseFee = FEE_DIVISOR - fee;

        uint numerator = reserveIn.mul(amountOut).mul(FEE_DIVISOR);
        uint denominator = reserveOut.sub(amountOut).mul(inverseFee);
        amountIn = (numerator / denominator).add(1);
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(address factory, uint amountIn, address token0, address token1, uint64 feeRebate) internal view returns (uint amountOut) {
        (uint reserveIn, uint reserveOut) = getReserves(factory, token0, token1);
        require(amountIn > 0, 'CobraDexLibrary: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'CobraDexLibrary: INSUFFICIENT_LIQUIDITY');

        address pair = pairFor(factory, token0, token1);
        uint FEE_DIVISOR = ICobraDexPair(pair).getFeeDivisor();
        uint fee = ICobraDexPair(pair).calculateFee(feeRebate);
        uint inverseFee = FEE_DIVISOR - fee;
        
        uint amountInWithFee = amountIn.mul(inverseFee);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(FEE_DIVISOR).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(address factory, uint amountOut, address[] memory path, uint64 feeRebate) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'CobraDexLibrary: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint i = path.length - 1; i > 0; i--) {
            amounts[i - 1] = getAmountIn(factory, amounts[i], path[i - 1], path[i], feeRebate);
        }
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(address factory, uint amountIn, address[] memory path, uint64 feeRebate) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'CobraDexLibrary: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            amounts[i + 1] = getAmountOut(factory, amounts[i], path[i], path[i + 1], feeRebate);
        }
    }
}

