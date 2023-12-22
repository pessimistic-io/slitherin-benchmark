// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUniswapV3Pool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function protocolFees() external view returns (uint128, uint128);
    function collectProtocol(
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128, uint128);
    function setFeeProtocol(uint8 feeProtocol0, uint8 feeProtocol1) external;
}
