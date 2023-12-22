// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
/**
 * Utilities for ERC20 internal functions
 */

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import "./IVault.sol";

contract ERC20Utils {
    using SafeERC20 for IERC20;

    // ===================
    //      ERRORS
    // ===================
    error InsufficientERC20Balance(uint256 requiredAmt, uint256 balanceOf);

    /**
     * Transfer from vault address to us, approve internally if needed
     * @param vault - The vault address
     * @param token - The token
     * @param amt - The amount
     */
    function _transferFromVault(
        address vault,
        IERC20 token,
        uint256 amt
    ) internal {
        _tryApproveSelf(vault, token, amt);
        token.transferFrom(vault, address(this), amt);
    }

    /**
     * Approve some token allowance (as the diamond) on a vault only if allownace is insufficient
     * @param vault - The vault address
     * @param token - The token
     * @param amt - The amount
     */
    function _tryApproveSelf(
        address vault,
        IERC20 token,
        uint256 amt
    ) internal {
        if (token.allowance(vault, address(this)) < amt)
            IVault(vault).approveDaddyDiamond(address(token), amt);
    }

    /**
     * Approve some token allownace on an external trusted contractr only if allowance is insufficient
     * @param token The token to approve on
     * @param target The contract to approve
     * @param amt The amount
     */
    function _tryApproveExternal(
        IERC20 token,
        address target,
        uint256 amt
    ) internal {
        if (token.allowance(address(this), target) < amt)
            token.approve(target, amt);
    }
}

