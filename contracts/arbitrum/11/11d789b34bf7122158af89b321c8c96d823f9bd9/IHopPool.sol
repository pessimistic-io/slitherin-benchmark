// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

interface IHopPool {
    function addLiquidity(
        uint256[] calldata amounts,
        uint256 minToMint,
        uint256 deadline
    ) external returns (uint256);
}
