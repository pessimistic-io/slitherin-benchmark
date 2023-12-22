// SPDX-License-Identifier: Unlicense
pragma solidity >=0.5.0;

/// @title An interface for a contract that is capable of deploying Uniswap V3 Pools
/// @notice A contract that constructs a pool must implement this to pass arguments to the pool
/// @dev This is used to avoid having constructor arguments in the pool contract, which results in the init code hash
/// of the pool being constant allowing the CREATE2 address of the pool to be cheaply computed on-chain
interface IWrapedTokenDeployer {
    /// @notice Get the parameters to be used in constructing the pool, set transiently during pool creation.
    /// Returns name
    /// Returns symbol
    /// Returns decimals
    function parameters()
        external
        returns (
            uint256 origin,
            bytes memory origin_hash,
            uint8 origin_decimals
        );
}
