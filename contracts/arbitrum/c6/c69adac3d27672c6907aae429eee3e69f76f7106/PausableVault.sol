// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

/// @title PausableVault
/// @author Umami DAO
/// @notice Pausable deposit/withdraw support for vaults
abstract contract PausableVault {
    /// @dev Emitted when the pause is triggered by `account`.
    event Paused(address account);

    /// @dev Emitted when the pause is lifted by `account`.
    event Unpaused(address account);

    /// @dev paused deposits only
    event DepositsPaused(address account);

    /// @dev paused deposits only
    event DepositsUnpaused(address account);

    /// @dev paused withdrawals only
    event WithdrawalsPaused(address account);

    /// @dev paused withdrawals only
    event WithdrawalsUnpaused(address account);

    bool private _depositsPaused;

    bool private _withdrawalPaused;

    /**
     * @dev Initializes the contract in unpaused state.
     */
    constructor() {
        _depositsPaused = false;
        _withdrawalPaused = false;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenDepositNotPaused() {
        _requireDepositNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenWithdrawalNotPaused() {
        _requireWithdrawalNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenDepositPaused() {
        _requireDepositPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenWithdrawalPaused() {
        _requireWithdrawalPaused();
        _;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function depositPaused() public view virtual returns (bool) {
        return _depositsPaused;
    }
    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */

    function withdrawalPaused() public view virtual returns (bool) {
        return _withdrawalPaused;
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireDepositNotPaused() internal view virtual {
        require(!depositPaused(), "Pausable: deposit paused");
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireWithdrawalNotPaused() internal view virtual {
        require(!withdrawalPaused(), "Pausable: withdrawal paused");
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requireDepositPaused() internal view virtual {
        require(depositPaused(), "Pausable: deposit not paused");
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requireWithdrawalPaused() internal view virtual {
        require(withdrawalPaused(), "Pausable: withdrawal not paused");
    }

    /**
     * @dev Triggers stopped state.
     */
    function _pause() internal virtual {
        if (!depositPaused()) {
            _pauseDeposit();
        }
        if (!withdrawalPaused()) {
            _pauseWithdrawal();
        }
        emit Paused(msg.sender);
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual {
        if (depositPaused()) {
            _unpauseDeposit();
        }
        if (withdrawalPaused()) {
            _unpauseWithdrawal();
        }
        emit Unpaused(msg.sender);
    }

    /**
     * @dev Triggers stopped deposit state.
     *
     * Requirements:
     *
     * - The deposits must not be paused.
     */
    function _pauseDeposit() internal virtual whenDepositNotPaused {
        _depositsPaused = true;
        emit Paused(msg.sender);
    }

    /**
     * @dev Returns to normal deposit state.
     *
     * Requirements:
     *
     * - The deposits must be paused.
     */
    function _unpauseDeposit() internal virtual whenDepositPaused {
        _depositsPaused = false;
        emit Unpaused(msg.sender);
    }

    /**
     * @dev Triggers stopped withdrawal state.
     *
     * Requirements:
     *
     * - The withdrawals must not be paused.
     */
    function _pauseWithdrawal() internal virtual whenWithdrawalNotPaused {
        _withdrawalPaused = true;
        emit Paused(msg.sender);
    }

    /**
     * @dev Returns to normal withdrawal state.
     *
     * Requirements:
     *
     * - The withdrawals must be paused.
     */
    function _unpauseWithdrawal() internal virtual whenWithdrawalPaused {
        _withdrawalPaused = false;
        emit Unpaused(msg.sender);
    }
}

