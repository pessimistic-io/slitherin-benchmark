// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.5.0;

/// @notice A CFMM liqudity share lending engine
/// @author Kyle Scott (https://github.com/numoen/core/blob/master/src/Lendgine.sol)
/// @author Modified from Uniswap (https://github.com/Uniswap/v3-core/blob/main/contracts/UniswapV3Pool.sol)
/// and Primitive (https://github.com/primitivefinance/rmm-core/blob/main/contracts/PrimitiveEngine.sol)
interface ILendgine {
    /// @notice The contract that deployed the lendgine
    function factory() external view returns (address);

    /// @notice The CFMM that is used in the lendgine
    function pair() external view returns (address);

    /// @notice Returns information about a position by the position's key
    function positions(address owner)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );

    /// @notice The total amount of liquidity that has been lent out
    function totalLiquidity() external view returns (uint256);

    /// @notice The currently borrowed liquidity by borrowers
    function totalLiquidityBorrowed() external view returns (uint256);

    /// @notice The amount of speculative assert rewarded to each unit of liquidity scaled by one ether
    function rewardPerLiquidityStored() external view returns (uint256);

    /// @notice The timestamp at which interest was last accrued
    function lastUpdate() external view returns (uint64);

    /// @notice Creates a position with amountS `speculative` tokens as collateral and `pair` CFMM share
    /// as debt, exactly replicating the desired payoff
    /// @dev This function uses a callback architecture capable of flash-minting
    /// @param to The address to mint the position to
    /// @param amountS The amount of `speculative` tokens to use as collateral, which determines
    /// the size of the position
    /// @param data Any data that should be passed through to the callback
    /// @return shares The size of the position that was sent to `to`
    function mint(
        address to,
        uint256 amountS,
        bytes calldata data
    ) external returns (uint256 shares);

    /// @notice Burns a position, paying back debt and refunding collateral to the `to` address
    /// @dev The position that is to be burned should be sent to this contract before invoking this function
    /// @dev This assumes there is at least the amount of debt that is owed by this position
    /// @param to The address to send the unlocked collateral to
    /// @return amountS The amount of `speculative` tokens that have been sent to the `to` address
    function burn(address to) external returns (uint256 amountS);

    /// @notice Deposit CFMM shares from the `pair` to be lent out
    /// @dev The appropriate position should be minted in the pair contract before invoking this function
    /// @param to The address for which the deposit will be owned by
    function deposit(address to) external;

    /// @notice Withdraw CFMM shares from the lending engine
    /// @dev The shares must still be withdrawn from the `pair`
    /// @param liquidity The amount of liquidity to remove
    function withdraw(uint256 liquidity) external;

    /// @notice Calculates the interest rate and amount of interest that has gathered since the last update,
    /// then charges the borrowers and pays the lenders
    /// @dev Only positive interest rates are allowed
    function accrueInterest() external;

    /// @notice Calculates the interest accrued by a specific postion
    /// @dev msg.sender is used to calculate the owner of the position
    function accruePositionInterest() external;

    /// @notice Collects tokens owed to a postion
    /// @dev msg.sender is used to calculative the owner of the position
    /// @param to The address to send the collected tokens to
    /// @param amountSRequested How much `speculative` tokens should be withdrawn from the tokens owed
    function collect(address to, uint256 amountSRequested) external returns (uint256 amountS);

    /// @notice Convert `pair` liquidity shares to amount of replicating derivative shares
    function convertLiquidityToShare(uint256 liquidity) external view returns (uint256);

    /// @notice Convert replicating derivative shares to `pair` liquidity shares
    function convertShareToLiquidity(uint256 shares) external view returns (uint256);

    /// @notice Convert `speculative` tokens to maximum amount of borrowable `pair` shares
    function convertAssetToLiquidity(uint256 assets) external view returns (uint256);

    /// @notice Convert `pair` liquidity shares to minimum amount of `speculative` collateral
    function convertLiquidityToAsset(uint256 liquidity) external view returns (uint256);

    /// @notice Returns the `speculative` balances of the lendgine
    /// @dev Not to be relied upon anywhere else because of a potential readonly reentracy
    function balanceSpeculative() external view returns (uint256);
}

