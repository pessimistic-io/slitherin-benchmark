// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IWombatRouter {

    function swapExactTokensForTokens(
        address[] calldata tokenPath,
        address[] calldata poolPath,
        uint256 amountIn,
        uint256 minimumamountOut,
        address to,
        uint256 deadline
    ) external;
    
    function getAmountOut(address[] calldata tokenPath, address[] calldata poolPath, uint256 amountIn)
        external
        view
        returns (uint256 amountOut, uint256[] memory haircuts);
}
