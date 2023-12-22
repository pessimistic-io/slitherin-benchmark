// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IPriceRouter {
    function getTokenPrice(address token, address itoken, uint256 amount) external view returns (uint256);
}

