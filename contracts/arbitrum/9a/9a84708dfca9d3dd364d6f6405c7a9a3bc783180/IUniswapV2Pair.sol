// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.5.0;

interface IUniswapV2Pair {
    function kLast() external view returns (uint);
    function price0CumulativeLast() external view returns (uint);
    function fee() external view returns (uint);
    function swapFee() external view returns (uint);
    function reserve0() external view returns (uint);
    function reserve1() external view returns (uint);
    function burn(address to) external returns (uint amount0, uint amount1);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function factory() external view returns (address);
    function transfer(address to, uint amount) external returns (bool);
    function balanceOf(address owner) external view returns(uint);
    function totalSupply() external view returns(uint);
    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast);
    function mint(address to) external returns (uint256 liquidity);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function sync() external;
}
