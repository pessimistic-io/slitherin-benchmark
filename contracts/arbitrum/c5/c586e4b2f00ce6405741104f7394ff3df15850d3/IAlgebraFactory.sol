// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;
pragma abicoder v2;

/// @title The interface for the Algebra Factory
/// @dev Credit to Uniswap Labs under GPL-2.0-or-later license:
/// https://github.com/Uniswap/v3-core/tree/main/contracts/interfaces
interface IAlgebraFactory {
    /// @notice Emitted when a pool is created
    /// @param token0 The first token of the pool by address sort order
    /// @param token1 The second token of the pool by address sort order
    /// @param pool The address of the created pool
    event Pool(address indexed token0, address indexed token1, address pool);

    /// @notice Emitted when the farming address is changed
    /// @param newFarmingAddress The farming address after the address was changed
    event FarmingAddress(address indexed newFarmingAddress);

    /// @notice Emitted when the default community fee is changed
    /// @param newDefaultCommunityFee The new default community fee value
    event DefaultCommunityFee(uint8 newDefaultCommunityFee);

    /// @notice role that can change communityFee and tickspacing in pools
    function POOLS_ADMINISTRATOR_ROLE() external view returns (bytes32);

    /// @dev Returns `true` if `account` has been granted `role` or `account` is owner.
    function hasRoleOrOwner(bytes32 role, address account) external view returns (bool);

    /// @notice Returns the current owner of the factory
    /// @dev Can be changed by the current owner via transferOwnership(address newOwner)
    /// @return The address of the factory owner
    function owner() external view returns (address);

    /// @notice Returns the current poolDeployerAddress
    /// @return The address of the poolDeployer
    function poolDeployer() external view returns (address);

    /// @dev Is retrieved from the pools to restrict calling certain functions not by a tokenomics contract
    /// @return The tokenomics contract address
    function farmingAddress() external view returns (address);

    /// @notice Returns the current communityVaultAddress
    /// @return The address to which community fees are transferred
    function communityVault() external view returns (address);

    /// @notice Returns the default community fee
    /// @return Fee which will be set at the creation of the pool
    function defaultCommunityFee() external view returns (uint8);

    /// @notice Returns the pool address for a given pair of tokens, or address 0 if it does not exist
    /// @dev tokenA and tokenB may be passed in either token0/token1 or token1/token0 order
    /// @param tokenA The contract address of either token0 or token1
    /// @param tokenB The contract address of the other token
    /// @return pool The pool address
    function poolByPair(address tokenA, address tokenB) external view returns (address pool);

    /**
     * @notice Creates a pool for the given two tokens and fee
     * @param tokenA One of the two tokens in the desired pool
     * @param tokenB The other of the two tokens in the desired pool
     * @dev tokenA and tokenB may be passed in either order: token0/token1 or token1/token0. tickSpacing is retrieved
     * from the fee. The call will revert if the pool already exists, the fee is invalid, or the token arguments
     * are invalid.
     * @return pool The address of the newly created pool
     */
    function createPool(address tokenA, address tokenB) external returns (address pool);
}

