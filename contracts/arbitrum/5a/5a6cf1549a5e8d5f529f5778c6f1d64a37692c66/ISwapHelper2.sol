// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

interface ISwapHelper2 {
    function calcSwapFee(address from, address to, uint256 amount)
        external
        view
        returns (uint256);

    function swap(address from, address to, uint256 amount, address recipient)
        external
        returns (uint256);
}

