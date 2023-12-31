// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {IWithdrawControlled} from "./IWithdrawControlled.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {AccessControl} from "./AccessControl.sol";

/**
 * An abstract contract that allows ETH and ERC20 tokens stored in the contract to be withdrawn.
 */
abstract contract WithdrawControlled is AccessControl, IWithdrawControlled {
    bytes32 public constant WITHDRAW_ROLE = keccak256("WITHDRAW_ROLE");

    //
    // Withdraw
    //

    /**
     * Withdraws ERC20 tokens owned by this contract.
     * @param token The ERC20 token address.
     * @param to Address to withdraw to.
     * @param value Amount to withdraw.
     * @notice Only callable by an address with the withdraw role.
     */
    function withdrawERC20(address token, address to, uint256 value) public onlyRole(WITHDRAW_ROLE) {
        SafeERC20.safeTransfer(IERC20(token), to, value);
    }

    /**
     * Withdraws ETH owned by this sale contract.
     * @param to Address to withdraw to.
     * @param value Amount to withdraw.
     * @notice Only callable by an address with the withdraw role.
     */
    function withdrawETH(address to, uint256 value) public onlyRole(WITHDRAW_ROLE) {
        (bool success,) = to.call{value: value}("");
        if (!success) {
            revert WithdrawFailed();
        }
    }
}

