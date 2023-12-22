// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.13;

import "./SafeERC20Upgradeable.sol";

import "./ISwapRouter.sol";
import "./IEtherealSpheresPool.sol";
import "./IRewardsDistributor.sol";

interface IFeeConverterV1 {
    error InvalidArrayLengths();
    error InvalidNumberOfTokens();

    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);
    event PathUpdated(address indexed token, bytes path);
    event ConversionCompleted(uint256 indexed reward);
    
    /// @notice Initializes the contract.
    /// @param swapRouter_ SwapRouter contract address.
    /// @param etherealSpheresPool_ EtherealSpheresPool contract address.
    /// @param weth_ WETH9 contract address.
    function initialize(
        ISwapRouter swapRouter_,
        IEtherealSpheresPool etherealSpheresPool_,
        IERC20Upgradeable weth_
    ) 
        external;
    
    /// @notice Updates the swap path for `token_`.
    /// @param token_ Token contract address.
    /// @param path_ Swap path.
    /// @param fees_ Pool fees.
    function updatePathForToken(
        address token_, 
        address[] calldata path_,
        uint256[] calldata fees_
    ) 
        external;
    
    /// @notice Removes token from conversion.
    /// @param token_ Token contract address.
    function removeToken(address token_) external;

    /// @notice Converts all tokens on the contract into WETH and notifies a reward in the pool.
    function convert() external;

    /// @notice Retrieves the number of tokens involved in conversion.
    function numberOfTokens() external view returns (uint256);

    /// @notice Retrieves the token involved in conversion by index.
    function getTokenAt(uint256 index_) external view returns (address);
}
