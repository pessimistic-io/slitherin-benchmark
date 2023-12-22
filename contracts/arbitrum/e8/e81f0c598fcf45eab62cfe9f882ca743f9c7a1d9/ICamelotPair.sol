// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICamelotPair {
    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint16 token0feePercent,
            uint16 token1FeePercent
        );
}
