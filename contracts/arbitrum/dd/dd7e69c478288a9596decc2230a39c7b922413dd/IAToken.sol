// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./IERC20.sol";

/// @title  IAToken
/// @author Savvy Defi
/// @dev Aave yield strategy token
interface IAToken is IERC20 {
    /**
     * @dev Returns the address of the underlying asset of this aToken (E.g. WETH for aWETH)
     **/
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);

    /**
     * @dev Returns the address of the lending pool.
     **/
    function POOL() external view returns (address);
}

