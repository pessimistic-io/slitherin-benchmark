// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Operations} from "./Operations.sol";
import {IPermissions} from "./IPermissions.sol";
import {IPayoutAddress} from "./IPayoutAddress.sol";
import {PayoutAddressStorage} from "./PayoutAddressStorage.sol";

/// @dev This contract provides utilities to manage collections' payout address
/// @notice It is not to be instantiated directly, but inherited by eg. PayoutAddressExtension
abstract contract PayoutAddress is IPayoutAddress {
    /*===========
        VIEWS
    ===========*/

    /// @inheritdoc IPayoutAddress
    function payoutAddress() public view virtual returns (address) {
        PayoutAddressStorage.Layout storage layout = PayoutAddressStorage.layout();
        return layout.payoutAddress;
    }

    /*=============
        SETTERS
    =============*/

    /// @inheritdoc IPayoutAddress
    function updatePayoutAddress(address newPayoutAddress) external virtual {
        _checkCanUpdatePayoutAddress();
        if (newPayoutAddress == address(0)) revert PayoutAddressIsZero();
        _updatePayoutAddress(newPayoutAddress);
    }

    /// @inheritdoc IPayoutAddress
    function removePayoutAddress() external virtual {
        _checkCanUpdatePayoutAddress();
        _updatePayoutAddress(address(0));
    }

    function _updatePayoutAddress(address newPayoutAddress) internal {
        PayoutAddressStorage.Layout storage layout = PayoutAddressStorage.layout();
        emit PayoutAddressUpdated(layout.payoutAddress, newPayoutAddress);
        layout.payoutAddress = newPayoutAddress;
    }

    /*====================
        AUTHORIZATION
    ====================*/

    /// @notice This function is meant to be invoked in the context of `delegatecall`
    function _checkCanUpdatePayoutAddress() internal virtual {
        IPermissions(address(this)).checkPermission(Operations.ADMIN, msg.sender);
    }
}

