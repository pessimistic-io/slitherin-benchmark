// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.5.0;

/// @notice A gas efficient and opinionated CFMM pair with the capped power invariant
/// @author Kyle Scott (https://github.com/numoen/core/blob/master/src/Pair.sol)
/// @author Modified from Uniswap (https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol)
/// and Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC20.sol)
interface IPair {
    /// @notice The contract that deployed the pair
    function factory() external view returns (address);

    /// @notice The associated lending market for these liquidity shares
    function lendgine() external view returns (address);

    /// @notice The base token of the pair
    function base() external view returns (address);

    /// @notice The speculative token of the pair
    function speculative() external view returns (address);

    /// @notice The scale of the base token
    function baseScaleFactor() external view returns (uint256);

    /// @notice The scale of the speculative token
    function speculativeScaleFactor() external view returns (uint256);

    /// @notice The upper price limit of the CFMM, the exchange rate offered by this pool will never exceed this value
    /// @dev Scaled by 10**18
    function upperBound() external view returns (uint256);

    /// @notice The total supply of CFMM shares
    function totalSupply() external view returns (uint256);

    /// @notice The amount of tokens that are currently unowned by the `lendgine`
    /// @dev This acts as the communication channel between the pair and lendgine, instead of implementing a full ERC20
    /// balance schematic, this buffer is used to express tokens that are about to be burned, deposited, or withdrawn
    function buffer() external view returns (uint256);

    /// @notice The amount of base tokens in the pool
    function reserve0() external view returns (uint120);

    /// @notice The amount of speculative tokens in the pool
    function reserve1() external view returns (uint120);

    /// @notice Verifies that the given amounts satisfy the trading invariant
    /// @param r0 The amount of `base` tokens
    /// @param r1 The amount of `speculative` tokens
    /// @param shares The amount of liquidity shares
    /// @return valid Whether or not the invariant passed
    function verifyInvariant(
        uint256 r0,
        uint256 r1,
        uint256 shares
    ) external view returns (bool valid);

    /// @notice Create a liquidity providing position
    /// @dev This assumes the amount of each token that is to be deposited has already been
    /// sent to this contract prior to invoking this function
    /// @param liquidity The amount of liquidity shares requested
    function mint(uint256 liquidity) external;

    /// @notice Destroy a liquidity providing position and receive the underlying balances
    /// @param to The address to receive the underlying balances
    /// @param liquidity The amount of liquidity shares to burn
    function burn(address to, uint256 liquidity) external returns (uint256 amount0, uint256 amount1);

    /// @notice Exchange between the `base` and `speculative` tokens, either accepts or rejects the proposed trade
    /// @dev The tokens that are to be sent to be sent in for the swap are required
    /// this contract before the invocation of this function
    /// @param to The address to receive the output of the trade
    /// @param amount0Out The amount of `base` tokens requested out of the trade
    /// @param amount1Out The amount of `speculative` tokens requested out of the trade
    function swap(
        address to,
        uint256 amount0Out,
        uint256 amount1Out
    ) external;

    /// @notice Removes any tokens that were donated to the pool;
    function skim(address to) external;

    /// @notice Adds liquidity shares to the buffer
    /// @dev Only callable by the lendgine, this is liquidity that is withdrawn from the lendgine but not the pair
    /// @param amount The amount of liquidity shares to add
    function addBuffer(uint256 amount) external;

    /// @notice Removes liquidity shares from the buffer
    /// @dev Only callable by the lendgine, this is takes liquidity that was minted in the pair
    /// and deposits it to the lendgine
    /// @param amount The amount of liquidity shares to remove
    function removeBuffer(uint256 amount) external;
}

