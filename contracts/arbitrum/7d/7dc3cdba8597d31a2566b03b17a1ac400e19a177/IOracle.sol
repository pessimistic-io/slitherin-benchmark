// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

interface IOracle {
    function update() external;

    function consult(address token, uint256 amountIn)
        external
        view
        returns (uint256 amountOut);
}
