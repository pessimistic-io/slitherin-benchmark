// SPDX-License-Identifier:  MIT
pragma solidity 0.8.17;

interface IPool {
    function swap(
        address from,
        address to,
        address recipient,
        uint256 amount,
        uint256 minAmount,
        uint256 deadline
    ) external;
}

