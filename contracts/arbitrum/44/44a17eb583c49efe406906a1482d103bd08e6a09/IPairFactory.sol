// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IPairFactory {
    function balanceOf(address account) external view returns (uint);
    function isPair(address pair) external view returns (bool);
    function getPair(address tokenA, address token, bool stable) external view returns (address);
    function createPair(address tokenA, address tokenB, bool stable) external returns (address pair);
    function claimFees() external returns (uint, uint);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (
        uint112 _reserve0,
        uint112 _reserve1,
        uint32 _blockTimestampLast
    );
}
