// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

interface IKyborgHubCallbacks {
    /// @notice Called by Kyborg hub to request for tokens to finish deposit
    /// @param token    Token that you are depositing
    /// @param amount   Amount that you are depositing
    /// @param data     Arbitrary data initially passed by you
    function kyborgDepositCallback(
        address token,
        uint256 amount,
        bytes calldata data
    ) external;

    /// @notice Called by Kyborg hub to request for tokens to finish minting liquidity
    /// @param token0   Token0 of the pool
    /// @param token1   Token1 of the pool
    /// @param amount0  Token0 amount you are owing to Kyborg
    /// @param amount1  Token1 amount you are owing to Kyborg
    /// @param data     Arbitrary data initially passed by you
    function kyborgMintCallback(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;

    /// @notice Called by Kyborg hub to request for tokens to finish swapping
    /// @param tokenIn      Input token
    /// @param tokenOut     Output token
    /// @param amountIn     Input token amount you are owing to Kyborg
    /// @param amountOut    Output token amount you have just received
    /// @param data         Arbitrary data initially passed by you
    function kyborgSwapCallback(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        bytes calldata data
    ) external;
}

