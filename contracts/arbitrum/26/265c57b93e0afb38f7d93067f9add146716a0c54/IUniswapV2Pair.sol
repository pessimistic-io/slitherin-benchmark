// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;


interface IUniswapV2Pair {

    function MINIMUM_LIQUIDITY() external view returns (uint256);

    function MAX_FEE() external view returns (uint256);

    function MAX_PROTOCOL_SHARE() external view returns (uint256);

    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint256 blockTimestampLast);

}

