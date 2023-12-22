pragma solidity ^0.8.3;
pragma experimental ABIEncoderV2;

/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Hegic
 * Copyright (C) 2021 Hegic Protocol
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 **/

import "./AccessControl.sol";

interface IPolymialPriceCaclulator {
    function setCoefficients(int256[5] calldata) external;
    function coefficients(uint256) external view returns (int256);
    function hasRole(bytes32, address) external view returns (bool);
}

contract PriceManager {
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    struct CoefficientSet {
        IPolymialPriceCaclulator pricer;
        int256[5] values;
    }

    function setCoefficients(CoefficientSet[] memory sets) external {
        for (uint i = 0; i < sets.length; i++) {
            IPolymialPriceCaclulator pricer = sets[i].pricer;
            require(pricer.hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "sender has no DEFAULT_ADMIN_ROLE");
            pricer.setCoefficients(sets[i].values);
        }
    }

    function readCoefficients(IPolymialPriceCaclulator[] calldata calculators) view external returns (int256[5][] memory) {
        int256[5][] memory result = new int256[5][](calculators.length);

        for (uint i = 0; i < calculators.length; i++) {
            IPolymialPriceCaclulator calc = calculators[i];
            for (uint j = 0; j < 5; j++) {
                result[i][j] = calc.coefficients(j);
            }
        }

        return result;
    }
}
