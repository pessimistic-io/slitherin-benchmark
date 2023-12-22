// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./IERC20.sol";

/// @title  IStaticAToken
/// @author Savvy Defi
interface IStaticAToken is IERC20 {
    function lendingPool() external view returns (address);

    function aToken() external view returns (address);

    function baseToken() external view returns (address);

    function deposit(
        address recipient,
        uint256 amount,
        uint16 referralCode,
        bool fromUnderlying
    ) external returns (uint256);

    function withdraw(
        address recipient,
        uint256 amount,
        bool toUnderlying
    ) external returns (uint256, uint256);

    /// @dev Converts a static amount (scaled balance on aToken) to the aToken/underlying value, using the current
    ///      liquidity index on Aave.
    ///
    /// @param amount The amount to convert from.
    ///
    /// @return dynamicAmount The dynamic amount.
    function staticToDynamicAmount(
        uint256 amount
    ) external view returns (uint256 dynamicAmount);

    /// @dev Converts an aToken or underlying amount to the what it is denominated on the aToken as scaled balance,
    ///      function of the principal and the liquidity index.
    ///
    /// @param amount The amount to convert from.
    ///
    /// @return staticAmount The static (scaled) amount.
    function dynamicToStaticAmount(
        uint256 amount
    ) external view returns (uint256 staticAmount);

    /// @dev Returns the Aave liquidity index of the underlying aToken, denominated rate here as it can be considered as
    ///      an ever-increasing exchange rate.
    ///
    /// @return The rate.
    function rate() external view returns (uint256);
}

