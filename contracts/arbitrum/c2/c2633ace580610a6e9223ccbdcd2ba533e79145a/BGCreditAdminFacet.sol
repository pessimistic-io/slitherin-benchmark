// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { DiamondOwnable } from "./DiamondOwnable.sol";
import { DiamondAccessControl } from "./DiamondAccessControl.sol";

// Storage imports
import { WithModifiers } from "./LibStorage.sol";
import { Errors } from "./Errors.sol";

contract BGCreditAdminFacet is WithModifiers {
    event CreditTypeSet(uint256 creditTypeId, bool state);
    event GFlyPerCreditSet(uint256 amount);
    event TreasuresPerCreditSet(uint256 amount);

    /**
     * @dev Sets the credit types eligible for credit creations given:
     * A list of credit type IDs
     * A list of states (true/false)
     */
    function setCreditTypes(uint256[] memory creditTypeIds, bool[] memory states) external onlyOwner {
        if (creditTypeIds.length != states.length) revert Errors.InvalidArrayLength();
        for (uint256 i = 0; i < creditTypeIds.length; i++) {
            gs().creditTypes[creditTypeIds[i]] = states[i];
            emit CreditTypeSet(creditTypeIds[i], states[i]);
        }
    }

    /**
     * @dev Sets the amount of gFLY to be used when creating a credit
     */
    function setGFlyPerCredit(uint256 amount) external onlyOwner {
        gs().gFlyPerCredit = amount;
        emit GFlyPerCreditSet(amount);
    }

    /**
     * @dev Sets the amount of Treasures to be used when creating a credit
     */
    function setTreasuresPerCredit(uint256 amount) external onlyOwner {
        gs().treasuresPerCredit = amount;
        emit TreasuresPerCreditSet(amount);
    }
}

