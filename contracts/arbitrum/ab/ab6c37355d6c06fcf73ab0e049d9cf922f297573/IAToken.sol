// SPDX-License-Identifier: AGPL-3.0
// https://github.com/aave/aave-v3-core/blob/6070e82d962d9b12835c88e68210d0e63f08d035/contracts/interfaces/IAToken.sol

pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {IScaledBalanceToken} from "./IScaledBalanceToken.sol";

/**
 * @title IAToken
 * @author Aave
 * @notice Defines the basic interface for an AToken.
 */
interface IAToken is IERC20, IScaledBalanceToken {
    /**
     * @notice Returns the address of the underlying asset of this aToken (E.g. WETH for aWETH)
     * @return The address of the underlying asset
     */
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}

