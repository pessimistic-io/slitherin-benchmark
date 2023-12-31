// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18} from "./UD60x18.sol";

interface IPricing {
    error Pricing__PriceCannotBeComputedWithinTickRange();
    error Pricing__PriceOutOfRange(UD60x18 lower, UD60x18 upper, UD60x18 marketPrice);
    error Pricing__UpperNotGreaterThanLower(UD60x18 lower, UD60x18 upper);
}

