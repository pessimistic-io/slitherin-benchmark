// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IVester {
    function vest(uint256 source, address target, address token, uint256 amount, uint256 initial, uint256 cliff, uint256 time)
        external;
}

