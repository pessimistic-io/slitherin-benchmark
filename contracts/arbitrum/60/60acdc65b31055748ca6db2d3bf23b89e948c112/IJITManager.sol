// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IJITManager {
    /// @notice Adds a WETH sell order to the WBTC-WETH 0.05% fee pool.
    /// @dev Only called by a trusted contract.
    function addLiquidity(bool isToken0) external;

    /// @notice Removes all previously added liquidity from the WBTC-WETH 0.05% fee pool.
    /// @dev Only called by a trusted contract.
    function removeLiquidity() external;

    /// @notice Allows an authorised keeper to balance the funds by selling WBTC for WETH.
    function swapTokens(
        address to,
        bytes calldata data,
        bool approveToken0
    ) external;
}

