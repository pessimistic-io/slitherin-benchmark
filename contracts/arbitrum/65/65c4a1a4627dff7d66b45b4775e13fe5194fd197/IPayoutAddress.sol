// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IPayoutAddress {
    // events
    event PayoutAddressUpdated(address oldPayoutAddress, address newPayoutAddress);

    // errors
    error PayoutAddressIsZero();

    /// @dev Returns the address of the current `payoutAddress` in storage
    function payoutAddress() external view returns (address);

    /// @dev Updates the current payout address to the provided `payoutAddress`
    function updatePayoutAddress(address payoutAddress) external;

    /// @dev Removes the current payout address, replacing it with address(0x0)
    function removePayoutAddress() external;
}

