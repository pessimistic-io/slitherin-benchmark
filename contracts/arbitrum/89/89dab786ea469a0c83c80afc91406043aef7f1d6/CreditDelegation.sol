// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {Context} from "./Context.sol";
import {Errors} from "./Errors.sol";
import {ICreditDelegation} from "./ICreditDelegation.sol";

/**
 * @title CreditDelegation
 * @author Tazz Labs, inspired by AAVE v3
 * @notice Implementation of CreditDelegation for Liability tokens
 */
abstract contract CreditDelegation is ICreditDelegation {
    // Map of borrow allowances (delegator => delegatee => borrowAllowanceAmount)
    mapping(address => mapping(address => uint256)) internal _borrowAllowances;

    // Reserved storage space to allow for layout changes in the future.
    uint256[10] private ______gap;

    /**
     * @dev Constructor.
     */
    constructor() {
        // Intentionally left blank
    }

    /// @inheritdoc ICreditDelegation
    function approveDelegation(address delegatee, uint256 amount) external override {
        _approveDelegation(msg.sender, delegatee, amount);
    }

    /// @inheritdoc ICreditDelegation
    function borrowAllowance(address fromUser, address toUser) external view override returns (uint256) {
        return _borrowAllowances[fromUser][toUser];
    }

    /**
     * @notice Updates the borrow allowance of a user on the specific debt token.
     * @param delegator The address delegating the borrowing power
     * @param delegatee The address receiving the delegated borrowing power
     * @param amount The allowance amount being delegated.
     */
    function _approveDelegation(
        address delegator,
        address delegatee,
        uint256 amount
    ) internal {
        _borrowAllowances[delegator][delegatee] = amount;
        emit BorrowAllowanceDelegated(delegator, delegatee, amount);
    }

    /**
     * @notice Decreases the borrow allowance of a user on the specific debt token.
     * @param delegator The address delegating the borrowing power
     * @param delegatee The address receiving the delegated borrowing power
     * @param amount The amount to subtract from the current allowance
     */
    function _decreaseBorrowAllowance(
        address delegator,
        address delegatee,
        uint256 amount
    ) internal {
        require(_borrowAllowances[delegator][delegatee] >= amount, Errors.NEGATIVE_DELEGATION_NOT_ALLOWED);
        _approveDelegation(delegator, delegatee, _borrowAllowances[delegator][delegatee] - amount);
    }
}

