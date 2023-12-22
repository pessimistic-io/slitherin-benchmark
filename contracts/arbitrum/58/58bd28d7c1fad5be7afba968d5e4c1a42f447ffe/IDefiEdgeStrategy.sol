// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IDefiEdgeStrategy {
    // events
    event Mint(address indexed user, uint256 share, uint256 amount0, uint256 amount1);
    event Burn(address indexed user, uint256 share, uint256 amount0, uint256 amount1);
    event Hold();
    event Rebalance(NewTick[] ticks);
    event PartialRebalance(PartialTick[] ticks);

    struct NewTick {
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0;
        uint256 amount1;
    }

    struct PartialTick {
        uint256 index;
        bool burn;
        uint256 amount0;
        uint256 amount1;
    }

    /**
     * @notice Adds liquidity to the primary range
     * @param _amount0 Amount of token0
     * @param _amount1 Amount of token1
     * @param _amount0Min Minimum amount of token0 to be minted
     * @param _amount1Min Minimum amount of token1 to be minted
     * @param _minShare Minimum amount of shares to be received to the user
     * @return amount0 Amount of token0 deployed
     * @return amount1 Amount of token1 deployed
     * @return share Number of shares minted
     */
    function mint(
        uint256 _amount0,
        uint256 _amount1,
        uint256 _amount0Min,
        uint256 _amount1Min,
        uint256 _minShare
    )
        external
        returns (
            uint256 amount0,
            uint256 amount1,
            uint256 share
        );

    /**
     * @notice Burn liquidity and transfer tokens back to the user
     * @param _shares Shares to be burned
     * @param _amount0Min Mimimum amount of token0 to be received
     * @param _amount1Min Minimum amount of token1 to be received
     * @return collect0 The amount of token0 returned to the user
     * @return collect1 The amount of token1 returned to the user
     */
    function burn(
        uint256 _shares,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) external returns (uint256 collect0, uint256 collect1);

    /**
     * @notice Rebalances the strategy
     * @param _swapData Swap data to perform exchange from 1inch
     * @param _existingTicks Array of existing ticks to rebalance
     * @param _newTicks New ticks in case there are any
     * @param _burnAll When burning into new ticks, should we burn all liquidity?
     */
    function rebalance(
        bytes calldata _swapData,
        PartialTick[] calldata _existingTicks,
        NewTick[] calldata _newTicks,
        bool _burnAll
    ) external;

    /**
     * @notice Withdraws funds from the contract in case of emergency
     * @dev only governance can withdraw the funds, it can be frozen from the factory permenently
     * @param _token Token to transfer
     * @param _to Where to transfer the token
     * @param _amount Amount to be withdrawn
     * @param _newTicks Ticks data to burn liquidity from
     */
    function emergencyWithdraw(
        address _token,
        address _to,
        uint256 _amount,
        NewTick[] calldata _newTicks
    ) external;

    /**
     * @notice Get's assets under management with realtime fees
     * @param _includeFee Whether to include pool fees in AUM or not. (passing true will also collect fees from pool)
     * @param amount0 Total AUM of token0 including the fees  ( if _includeFee is passed true)
     * @param amount1 Total AUM of token1 including the fees  ( if _includeFee is passed true)
     * @param totalFee0 Total fee of token0 including the fees  ( if _includeFee is passed true)
     * @param totalFee1 Total fee of token1 including the fees  ( if _includeFee is passed true)
     */
    function getAUMWithFees(bool _includeFee)
        external
        view
        returns (
            uint256 amount0,
            uint256 amount1,
            uint256 totalFee0,
            uint256 totalFee1
    );

    function totalSupply() external view returns (uint256);
    function pool() external view returns(address);
    function manager() external view returns (address);
}
