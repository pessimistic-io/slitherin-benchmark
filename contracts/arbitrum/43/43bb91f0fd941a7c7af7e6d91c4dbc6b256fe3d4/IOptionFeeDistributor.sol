// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IOptionFeeDistributor {
    function distribute(address token, uint256 amount) external;
}

