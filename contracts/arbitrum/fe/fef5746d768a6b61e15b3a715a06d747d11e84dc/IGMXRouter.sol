// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

/// @title IGMXRouter Interface
/// @notice An interface for the GmxRouter smart contract, providing functions
/// for staking, unstaking, compounding, and claiming fees.
interface IGMXRouter {
    /// @notice Stakes the specified amount of GMX tokens.
    /// @param amount The amount of GMX tokens to stake.
    function stakeGmx(uint256 amount) external;

    /// @notice Unstakes the specified amount of GMX tokens.
    /// @param amount The amount of GMX tokens to unstake.
    function unstakeGmx(uint256 amount) external;

    /// @notice Compounds staked GMX tokens.
    function compound() external;

    /// @notice Claims fees from the contract.
    function claimFees() external;

    /// @notice Mints and stakes GLP tokens.
    /// @param _token The address of the token.
    /// @param _amount The amount of tokens to mint and stake.
    /// @param _minUsdg The minimum amount of USDG tokens to receive.
    /// @param _minGlp The minimum amount of GLP tokens to receive.
    /// @return The actual amount of GLP tokens minted and staked.
    function mintAndStakeGlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdg,
        uint256 _minGlp
    ) external returns (uint256);

    /// @notice Unstakes and redeems GLP tokens.
    /// @param _tokenOut The address of the token to receive.
    /// @param _glpAmount The amount of GLP tokens to unstake and redeem.
    /// @param _minOut The minimum amount of tokens to receive.
    /// @param _receiver The address to receive the tokens.
    /// @return The actual amount of tokens received.
    function unstakeAndRedeemGlp(
        address _tokenOut,
        uint256 _glpAmount,
        uint256 _minOut,
        address _receiver
    ) external returns (uint256);

    /// @notice Gets the address of the fee GLP tracker.
    /// @return The address of the fee GLP tracker.
    function feeGlpTracker() external view returns (address);

    /// @notice Gets the address of the fee GMX tracker.
    /// @return The address of the fee GMX tracker.
    function feeGmxTracker() external view returns (address);

    /// @notice Gets the address of the staked GMX tracker.
    /// @return The address of the staked GMX tracker.
    function stakedGmxTracker() external view returns (address);

    /// @notice Gets the address of the GLP manager.
    /// @return The address of the GLP manager.
    function glpManager() external view returns (address);

    /// @notice Gets the address of the GLP token.
    /// @return The address of the GLP token.
    function glp() external view returns (address);

    /// @notice Signals a transfer of ownership.
    /// @param _receiver The address of the new owner.
    function signalTransfer(address _receiver) external;

    /// @notice Accepts the transfer of ownership.
    /// @param _sender The address of the current owner.
    function acceptTransfer(address _sender) external;
}

