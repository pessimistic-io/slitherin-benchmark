// SPDX-License-Identifier: NONE
pragma solidity 0.8.10;

import "./console.sol";
import "./LibStorage.sol";
import {LibAccessControl} from "./LibAccessControl.sol";

/**
 * Handles token price information
 */

contract PriceFacet is WithStorage, WithModifiers {
    /// @notice Sets the native token's price in USD
    /// @param price price in USD (x1000 for precision)
    function setNativeTokenPriceInUsd(uint256 price)
        external
        roleOnly(LibAccessControl.Roles.BORIS)
    {
        _ps().nativeTokenPriceInUsd = price;
    }

    // Returns the USD cost of creating a character (x1000 for precision)
    function getNativeTokenPriceInUsd() public view returns (uint256) {
        return _ps().nativeTokenPriceInUsd;
    }
}

