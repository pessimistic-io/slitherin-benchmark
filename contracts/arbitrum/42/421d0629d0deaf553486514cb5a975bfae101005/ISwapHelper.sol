// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

interface ISwapHelper {
    function swap(address _token, uint256 _amount) external returns (uint256);
}

