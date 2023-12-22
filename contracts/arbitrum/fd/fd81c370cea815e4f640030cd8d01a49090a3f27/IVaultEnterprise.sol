// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.6;

interface IVaultEnterprise {
    event Deposit(address);
    event CollectPoolFees(uint256, uint256);
    event Rebalance(int24, uint256, uint256, uint256, uint256, uint256);
    event SetFee(uint16);
    event ToggledPauseStatus();
    event Withdrawal(address, address, uint256, uint256, uint256);

    // function swapAndDeposit(
    //     // The `sellTokenAddress` field from the API response.
    //     IERC20 sellToken,
    //     // The amount of sellToken we want to sell
    //     uint256 sellAmount,
    //     // The `buyTokenAddress` field from the API response.
    //     IERC20 buyToken,
    //     // The `allowanceTarget` field from the API response.
    //     address spender,
    //     // The `to` field from the API response.
    //     address payable swapTarget,
    //     // The `data` field from the API response.
    //     bytes calldata swapCallData,
    //     address _from,
    //     address _to,
    //     uint256 _amount0Minimum,
    //     uint256 _amount1Minimum
    // ) external payable nonReentrant onlyWhitelisted {
    //     vaultSwap.fillQuote(
    //         sellToken,
    //         sellAmount,
    //         buyToken,
    //         spender,
    //         swapTarget,
    //         swapCallData
    //     );
    // }

    // function deposit(
    //     uint256 _amount0,
    //     uint256 _amount1,
    //     address _from,
    //     address _to,
    //     uint256 _amount0Minimum,
    //     uint256 _amount1Minimum
    // ) external payable returns (uint256 shares);

    /// @param _shares Number of liquidity tokens to redeem as pool assets
    /// @param _to Address to which redeemed pool assets are sent
    /// @param _from Address from which liquidity tokens are sent
    /// @return _amount0 Amount of token0 redeemed by the submitted liquidity tokens
    /// @return _amount1 Amount of token1 redeemed by the submitted liquidity tokens
    function withdraw(
        uint256 _shares,
        address _to,
        address _from,
        uint256 _amount0Minimum,
        uint256 _amount1Minimum
    ) external returns (uint256 _amount0, uint256 _amount1);

    /// @notice Compound pool fees and distribute management fees
    /// @return _amount0Minted Quantity of addition token0 minted in the pool
    /// @return _amount1Minted Quantity of addition token1 minted in the pool
    function compound()
        external
        returns (uint256 _amount0Minted, uint256 _amount1Minted);

    /// @param _tickLower The lower tick of the rebalanced position
    /// @param _tickUpper The upper tick of the rebalanced position
    function rebalance(int24 _tickLower, int24 _tickUpper) external;

    /// @notice gets the User assets in the vault excluding non-compung fees
    /// @return _amount0ForShares Quantity of token0 owned by the user
    /// @return _amount1ForShares Quantity of token1 owned by the user
    function getUserPositionDetails(
        address _user
    )
        external
        view
        returns (uint256 _amount0ForShares, uint256 _amount1ForShares);

    /// @notice Callback function of uniswapV3Pool mint
    function uniswapV3MintCallback(
        uint256 _amount0,
        uint256 _amount1,
        bytes calldata _data
    ) external;

    /// @notice set the management fee
    /// @param _managementFee New Fee
    function setManagementFee(uint16 _managementFee) external;

    /// @notice pause or unpause the contract
    function togglePause() external;
}

