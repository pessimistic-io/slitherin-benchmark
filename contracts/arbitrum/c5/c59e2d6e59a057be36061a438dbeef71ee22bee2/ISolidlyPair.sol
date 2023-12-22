// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface ISolidlyPair {
    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function burn(address to) external returns (uint256 amount0, uint256 amount1);

    function sync() external;

    function getReserves()
    external
    view
    returns (
        uint112 reserve0,
        uint112 reserve1,
        uint32 blockTimestampLast
    );

    function stable() external view returns (bool);

    function getAmountOut(uint256 amountIn, address tokenIn) external view returns (uint256);
}
