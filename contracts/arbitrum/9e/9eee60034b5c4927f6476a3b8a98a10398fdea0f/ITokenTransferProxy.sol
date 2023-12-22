// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITokenTransferProxy {
    function transferFrom(address token, address from, address to, uint256 amount) external;
}

