// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

/// @title The interface for the Uniswap V3 and Algebra Factory
/// @notice The Uniswap V3 Factory facilitates creation of Uniswap V3 pools and control over the protocol fees
interface IUniversalV3Factory {
    /// @notice Return Uniswap V3 pool types
    /// @notice Returns the pool address for a given pair of tokens and a fee, or address 0 if it does not exist
    /// @dev tokenA and tokenB may be passed in either token0/token1 or token1/token0 order
    /// @return pool The pool address
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);

    /// @notice Return Alegbra pool types
    /// @notice Returns the pool address for a given pair of tokens and a fee, or address 0 if it does not exist
    /// @dev tokenA and tokenB may be passed in either token0/token1 or token1/token0 order
    /// @return pool The pool address
    function poolByPair(address tokenA, address tokenB) external view returns (address pool);

}
