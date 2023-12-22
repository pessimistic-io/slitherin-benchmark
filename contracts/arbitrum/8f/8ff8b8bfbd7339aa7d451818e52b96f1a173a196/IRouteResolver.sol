// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface IRouteResolver {
    function validateData(
        address from,
        address to,
        bytes calldata data
    ) external pure;

    function resolveSwapExactTokensForTokens(
        uint256 amountIn,
        bytes calldata data,
        address recipient
    ) external view returns (address, bytes memory);

    function getAmountOut(uint256 _amountIn, bytes calldata _data)
        external
        view
        returns (uint256);
}

