// SPDX-License-Identifier: BUSL-1.1
// See bluejay.finance/license
pragma solidity ^0.8.4;

import "./CreditLineBase.sol";

/// @title CreditLineBalloon
/// @author Bluejay Core Team
/// @notice Credit line for loans that pays only interest up till the final repayment
/// where both interest and principal is made in full
/// @dev Balloon loan is type 2
contract CreditLineBalloon is CreditLineBase {
    /// @notice Adjusts minimum payment in each period to just interest amount
    function _afterDrawdown() internal override {
        // Adjust minimum payment according to interest payments only
        minPaymentPerPeriod = interestOnBalance(paymentPeriod);
    }
}

