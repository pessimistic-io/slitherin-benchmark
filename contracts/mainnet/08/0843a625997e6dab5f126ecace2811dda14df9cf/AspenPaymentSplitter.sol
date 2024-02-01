// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8;

//  ==========  External imports    ==========
import "./PaymentSplitterUpgradeable.sol";
import "./Address.sol";

import "./BaseAspenPaymentSplitterV1.sol";
import "./errors_IErrors.sol";

contract AspenPaymentSplitter is PaymentSplitterUpgradeable, BaseAspenPaymentSplitterV1 {
    mapping(address => bool) private payeeExists;

    function initialize(address[] memory _payees, uint256[] memory _shares) external initializer {
        if (_payees.length != _shares.length) revert PayeeSharesArrayMismatch(_payees.length, _shares.length);
        uint256 totalShares = 0;
        for (uint256 i = 0; i < _shares.length; i++) {
            totalShares = totalShares + _shares[i];

            if (payeeExists[_payees[i]] == true) revert PayeeAlreadyExists(_payees[i]);
            payeeExists[_payees[i]] = true;
        }

        if (totalShares != 10000) revert InvalidTotalShares(totalShares);

        __PaymentSplitter_init(_payees, _shares);
    }

    /// ==================================
    /// ========== Relase logic ==========
    /// ==================================
    /// @dev Triggers a transfer to `account` of the amount of Ether they are owed, according to their percentage of the
    ///     total shares and their previous withdrawals.
    /// @param account - The address of the payee to release funds to.
    function releasePayment(address payable account) external override {
        release(account);
    }

    /// @dev Triggers a transfer to `account` of the amount of `token` tokens they are owed, according to their
    ///     percentage of the total shares and their previous withdrawals. `token` must be the address of an IERC20
    ///     contract.
    /// @param token - the address of an IERC20 contract.
    /// @param account - The address of the payee to release funds to.
    function releasePayment(IERC20Upgradeable token, address account) external override {
        release(token, account);
    }

    /// ======================================
    /// ========== Getter functions ==========
    /// ======================================
    /// @dev Getter for the total amount of Ether already released.
    function getTotalReleased() external view override returns (uint256) {
        return totalReleased();
    }

    /// @dev Getter for the total amount of `token` already released.
    /// @param token - the address of an IERC20 contract.
    function getTotalReleased(IERC20Upgradeable token) external view override returns (uint256) {
        return totalReleased(token);
    }

    /// @dev Getter for the amount of Ether already released to a payee.
    /// @param account - The address of the payee to check the funds that can be released to.
    function getReleased(address account) external view override returns (uint256) {
        return released(account);
    }

    /// @dev Getter for the total amount of `token` already released.
    /// @param token - the address of an IERC20 contract.
    /// @param account - The address of the payee to check the funds that can be released to.
    function getReleased(IERC20Upgradeable token, address account) external view override returns (uint256) {
        return released(token, account);
    }

    /// @dev Getter for the total amount of Ether that can be released for an account.
    /// @param account - The address of the payee to check the funds that can be released to.
    function getPendingPayment(address account) external view override returns (uint256) {
        if (shares(account) == 0) return 0;
        uint256 totalReceived = address(this).balance + totalReleased();

        return _getPendingPayment(account, totalReceived, released(account));
    }

    /// @dev Getter for the total amount of `token` that can be released for an account.
    /// @param token - the address of an IERC20 contract.
    /// @param account - The address of the payee to check the funds that can be released to.
    function getPendingPayment(IERC20Upgradeable token, address account) external view override returns (uint256) {
        if (shares(account) == 0) return 0;
        uint256 totalReceived = token.balanceOf(address(this)) + totalReleased(token);

        return _getPendingPayment(account, totalReceived, released(token, account));
    }

    /// @dev internal logic for computing the pending payment of an `account` given the token historical balances and
    ///     already released amounts.
    ///     private logic taken from _pendingPayment() function from openzeppelin/contracts-upgradeable/finance/PaymentSplitterUpgradeable.sol
    function _getPendingPayment(
        address account,
        uint256 totalReceived,
        uint256 alreadyReleased
    ) internal view returns (uint256) {
        return (totalReceived * shares(account)) / totalShares() - alreadyReleased;
    }

    /// ======================================
    /// =========== Miscellaneous ============
    /// ======================================
    /// @dev Provides a function to batch together multiple calls in a single external call.
    function multicall(bytes[] calldata data) external virtual override returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            results[i] = Address.functionDelegateCall(address(this), data[i]);
        }
        return results;
    }

    /// @dev Concrete implementation semantic version -
    ///         provided for completeness but not designed to be the point of dispatch
    function minorVersion() public pure override returns (uint256 minor, uint256 patch) {
        minor = 0;
        patch = 0;
    }
}

