// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import { Constants } from "./Constants.sol";

library TauMath {
    /**
     * @dev function to calculate the collateral ratio of an account.
     * @param _coll is amount of user collateral. Always has 18 decimals.
     * @param _debt is amount of user debt. Always has 18 decimals.
     * @param _price is $ / collateral. Has a precision of 10 ** priceDecimals.
     * @param priceDecimals is the number of decimals in the price.
     */
    function _computeCR(
        uint256 _coll,
        uint256 _debt,
        uint256 _price,
        uint8 priceDecimals
    ) internal pure returns (uint256) {
        if (_debt > 0) {
            uint256 collateralDollarValue = (_coll * _price) / 10 ** priceDecimals;
            uint256 newCollRatio = (collateralDollarValue * Constants.PRECISION) / _debt;

            return newCollRatio;
        }
        // Return the maximal value for uint256 if the account has a debt of 0. Represents "infinite" CR.
        else {
            // if (_debt == 0)
            return type(uint256).max;
        }
    }
}

