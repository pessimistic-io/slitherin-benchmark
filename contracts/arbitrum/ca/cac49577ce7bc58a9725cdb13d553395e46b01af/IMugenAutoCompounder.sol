// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IMugenAutoCompounder {
    function totalAssets() external view returns (uint256);
    function compoundMGN() external;
    function estimateAmoutOut() external view returns (uint256 amountOut);
}

