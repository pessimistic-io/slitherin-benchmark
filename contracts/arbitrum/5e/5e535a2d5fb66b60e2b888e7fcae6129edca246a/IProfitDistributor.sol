// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IProfitDistributor {
    function distribute(address token, uint256 amount) external;
}

