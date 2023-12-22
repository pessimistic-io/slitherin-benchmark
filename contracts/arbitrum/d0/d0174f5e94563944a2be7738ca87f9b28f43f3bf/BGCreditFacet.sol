// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Storage imports
import { WithModifiers } from "./LibStorage.sol";
import { Errors } from "./Errors.sol";

// Library imports
import { LibCreditUtils } from "./LibCreditUtils.sol";

// Contract imports
import { ReentrancyGuard } from "./ReentrancyGuard.sol";

contract BGCreditFacet is WithModifiers, ReentrancyGuard {
    event CreditCreated(
        address indexed account,
        uint256 indexed creditType,
        uint256 amount,
        bool redeemGFly,
        uint256[] treasureIds,
        uint256[] treasureAmounts
    );

    event InventorySlotUpgraded(address indexed account,
        uint256 indexed battleflyId,
        uint256 amount,
        bool redeemGFly,
        uint256[] treasureIds,
        uint256[] treasureAmounts);

    /**
     * @dev Create 1 or more in game credit(s) given:
     * A credit type
     * The amount of credits
     * If gFLY should be used to create the credit(s)
     * In case treasures should be used to create the credit(s): The treasure types to be used
     * In case treasures should be used to create the credit(s): The amount of treasures per type to be used
     */
    function createCredit(
        uint256 creditType,
        uint256 amount,
        bool redeemGFly,
        uint256[] memory treasureIds,
        uint256[] memory treasureAmounts
    ) external notPaused nonReentrant {
        // Disabled for initial launch
       // LibCreditUtils.createCredit(creditType, amount, redeemGFly, treasureIds, treasureAmounts);
       // emit CreditCreated(msg.sender, creditType, amount, redeemGFly, treasureIds, treasureAmounts);
    }

    /**
    * @dev Upgrade an inventory slot for a battlefly:
     * A battlefly ID
     * The amount slots to upgrade
     * If gFLY should be used to upgrade the slots
     * In case treasures should be used to upgrade the slots: The treasure types to be used
     * In case treasures should be used to upgrade the slots: The amount of treasures per type to be used
     */
    function upgradeInventorySlot(
        uint256 battleflyId,
        uint256 amount,
        bool redeemGFly,
        uint256[] memory treasureIds,
        uint256[] memory treasureAmounts
    ) external notPaused nonReentrant {
        LibCreditUtils.upgradeInventorySlot(amount, redeemGFly, treasureIds, treasureAmounts);
        emit InventorySlotUpgraded(msg.sender, battleflyId, amount, redeemGFly, treasureIds, treasureAmounts);
    }

    /**
     * @dev Checks if a credit type is a valid type for credit creations
     */
    function isCreditType(uint256 creditTypeId) external view returns (bool) {
        return gs().creditTypes[creditTypeId];
    }

    /**
     * @dev Returns the amount of gFLY required for 1 credit
     */
    function getGFlyPerCredit() external view returns (uint256) {
        return gs().gFlyPerCredit;
    }

    /**
     * @dev Returns the amount of treasures required for 1 credit
     */
    function getTreasuresPerCredit() external view returns (uint256) {
        return gs().treasuresPerCredit;
    }

    /**
     * @dev Returns the receiver of the gFLY used for credit creations
     */
    function getGFlyReceiver() external view returns (address) {
        return gs().gFlyReceiver;
    }

    /**
     * @dev Returns the receiver of the Treasures used for credit creations
     */
    function getTreasureReceiver() external view returns (address) {
        return gs().treasureReceiver;
    }

    /**
     * @dev Returns the gFLY address
     */
    function gFlyAddress() external view returns (address) {
        return gs().gFLY;
    }

    /**
     * @dev Returns the Treasures address
     */
    function treasuresAddress() external view returns (address) {
        return gs().treasures;
    }
}

