// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IKyberRouter {
    function weth() external pure returns (address);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata poolsPath,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata poolsPath,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

