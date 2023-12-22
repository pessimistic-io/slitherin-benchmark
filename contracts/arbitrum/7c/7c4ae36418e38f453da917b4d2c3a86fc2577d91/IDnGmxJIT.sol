// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IDnGmxJIT {
    /// @notice Adds a WETH sell order to the WBTC-WETH 0.05% fee pool.
    /// @dev Only called by a trusted contract.
    function addLiquidity() external;

    /// @notice Removes all previously added liquidity from the WBTC-WETH 0.05% fee pool.
    /// @dev Only called by a trusted contract.
    function removeLiquidity() external;

    /// @notice Allows an authorised keeper to balance the funds by selling WBTC for WETH.
    function swapWbtc(address to, bytes calldata data) external;
}

