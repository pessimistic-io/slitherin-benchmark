// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Storage imports
import { WithModifiers, PaymentType } from "./LibStorage.sol";
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
        PaymentType paymentType,
        uint256[] treasureIds,
        uint256[] treasureAmounts
    );

    event InventorySlotUpgraded(
        address indexed account,
        uint256 indexed battleflyId,
        uint256 amount,
        PaymentType paymentType,
        uint256[] treasureIds,
        uint256[] treasureAmounts
    );

    /**
     * @dev Create 1 or more in game credit(s) given:
     * A credit type
     * The amount of credits
     * What type of payment should be used to create the credit(s)
     * In case treasures should be used to create the credit(s): The treasure types to be used
     * In case treasures should be used to create the credit(s): The amount of treasures per type to be used
     */
    function createCredit(
        uint256 creditType,
        uint256 amount,
        PaymentType paymentType,
        uint256[] memory treasureIds,
        uint256[] memory treasureAmounts
    ) external notPaused nonReentrant {
        // Disabled for initial launch
        // LibCreditUtils.createCredit(creditType, amount, paymentType, treasureIds, treasureAmounts);
        // emit CreditCreated(msg.sender, creditType, amount, paymentType, treasureIds, treasureAmounts);
    }

    /**
     * @dev Upgrade an inventory slot for a battlefly:
     * A battlefly ID
     * The amount slots to upgrade
     * What type of payment should be used to upgrade the slots
     * In case treasures should be used to upgrade the slots: The treasure types to be used
     * In case treasures should be used to upgrade the slots: The amount of treasures per type to be used
     */
    function upgradeInventorySlot(
        uint256 battleflyId,
        uint256 amount,
        PaymentType paymentType,
        uint256[] memory treasureIds,
        uint256[] memory treasureAmounts
    ) external notPaused nonReentrant {
        LibCreditUtils.upgradeInventorySlot(amount, paymentType, treasureIds, treasureAmounts);
        emit InventorySlotUpgraded(msg.sender, battleflyId, amount, paymentType, treasureIds, treasureAmounts);
    }

    /**
     * @dev Checks if a credit type is a valid type for credit creations
     */
    function isCreditType(uint256 creditTypeId) external view returns (bool) {
        return gs().creditTypes[creditTypeId];
    }

    /**
     * @dev Returns the amount of Magic required for 1 credit
     */
    function getMagicPerCredit() external view returns (uint256) {
        return gs().magicPerCredit;
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
     * @dev Returns the receiver of the Magic used for credit creations
     */
    function getMagicReceiver() external view returns (address) {
        return gs().gFlyReceiver;
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
     * @dev Returns the receiver of the LP tokens
     */
    function getLpReceiver() external view returns (address) {
        return gs().lpReceiver;
    }

    /**
     * @dev Returns the Magic address
     */
    function magicAddress() external view returns (address) {
        return gs().magic;
    }

    /**
     * @dev Returns the gFLY address
     */
    function gFlyAddress() external view returns (address) {
        return gs().gFLY;
    }

    /**
     * @dev Returns the Magic/gFLY LP address
     */
    function magicGFlyLpAddress() external view returns (address) {
        return gs().magicGFlyLp;
    }

    /**
     * @dev Returns the MagicSwap router address
     */
    function magicSwapRouter() external view returns (address) {
        return gs().magicSwapRouter;
    }

    /**
     * @dev Returns the Treasures address
     */
    function treasuresAddress() external view returns (address) {
        return gs().treasures;
    }

    /**
     * @dev Returns amount of Magic reserved for LP swaps
     */
    function getMagicForLp() external view returns (uint256) {
        return gs().magicForLp;
    }

    /**
     * @dev Restuns the minimal amount of Magic required to perform automatic LP swaps
     */
    function getMagicLpTreshold() external view returns (uint256) {
        return gs().magicLpTreshold;
    }

    /**
     * @dev Returns amount of gFLY reserved for LP swaps
     */
    function getGFlyForLp() external view returns (uint256) {
        return gs().gFlyForLp;
    }

    /**
     * @dev Restuns the minimal amount of gFLY required to perform automatic LP swaps
     */
    function getGFlyLpTreshold() external view returns (uint256) {
        return gs().gFlyLpTreshold;
    }

    /**
     * @dev Gets the BPS denominator
     */
    function getBPSDenominator() external view returns (uint256) {
        return gs().bpsDenominator;
    }

    /**
     * @dev Gets the slippage in BPS
     */
    function getSlippageInBPS() external view returns (uint256) {
        return gs().slippageInBPS;
    }
}

