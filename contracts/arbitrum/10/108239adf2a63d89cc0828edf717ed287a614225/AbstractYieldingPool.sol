// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./EnumerableSet.sol";
import "./console.sol";

import "./AbstractPool.sol";
import "./IYieldingPool.sol";

abstract contract AbstractYieldingPool is IYieldingPool, AbstractPool {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSet for EnumerableSet.AddressSet;

    // ==============================================================================================
    /// Protocol Transactional Functions
    // ==============================================================================================
    /**
     * @notice Pushes tokens in the pool balance to the underlying protocol.
     * @param assetAddress Tokens to push
     * @param amount Amounts of tokens to push
     * @param options Additional options for the underlying protocol
     * @return actualTokenAmounts The amounts actually invested. It could be less than tokenAmounts
     * 
     */
    function push(
        address assetAddress,
        uint256 amount,
        bytes memory options
    ) virtual external returns (uint256 actualTokenAmounts);

    /**
     * @notice Pulls tokens from the underlying protocol into the pool
     * @param assetAddress Tokens to pull
     * @param amount Amounts of tokens to pull
     * @param options Additional options for the underlying protocol
     * @return actualTokenAmounts The amounts actually withdrawn. It could be less than tokenAmounts
     */
    function pull(
        address assetAddress,
        uint256 amount,
        bytes memory options
    ) virtual external returns (uint256 actualTokenAmounts);

    /**
     * @notice Claims the rewards from the pool
     * @param options Additional options for the underlying protocol
     * @return rewardAmount The amount actually withdrawn
     */
    function claimRewards(
        bytes memory options
    ) virtual public returns (uint256);


    /**
     * @notice Compounds the yield pool
     */
    function compound() virtual public;

    // ==============================================================================================
    /// Events
    // ==============================================================================================
    /**
     * @dev Emitted on push()
     * @param reserve The address of the underlying asset of the reserve
     * @param amount The amount pushed
     **/
    event Push(
        address reserve,
        uint256 amount
    );

    /**
     * @dev Emitted on pull()
     * @param reserve The address of the underlying asset of the reserve
     * @param user The address of the receipent
     * @param amount The amount pulled
     **/
    event Pull(
        address reserve,
        address user,
        uint256 amount
    );
}
