// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IGmxVault {
    function swap(address _tokenIn, address _tokenOut, address _receiver) external returns (uint256);
}

