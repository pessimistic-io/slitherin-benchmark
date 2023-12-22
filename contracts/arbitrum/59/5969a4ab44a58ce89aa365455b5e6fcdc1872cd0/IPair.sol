// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface IPair {
    function metadata()
        external
        view
        returns (
            uint256 dec0,
            uint256 dec1,
            uint256 r0,
            uint256 r1,
            bool st,
            address t0,
            address t1
        );
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;
    function current(
        address tokenIn,
        uint256 amountIn
    ) external view returns (uint256 amountOut);
    function mint(address to) external returns (uint256 liquidity);
}
