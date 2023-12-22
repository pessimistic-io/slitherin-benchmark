// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface I1Inch {
    function swap(
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 minReturn,
        uint256[] memory distribution,
        uint256 flags
    ) external payable;
}

