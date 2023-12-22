// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { DiamondOwnable } from "./DiamondOwnable.sol";
import { DiamondAccessControl } from "./DiamondAccessControl.sol";

// Library imports
import { LibCreditUtils } from "./LibCreditUtils.sol";

//interfaces
import { IERC20 } from "./IERC20.sol";

// Storage imports
import { WithModifiers } from "./LibStorage.sol";
import { Errors } from "./Errors.sol";

contract BGCreditAdminFacet is WithModifiers {
    event CreditTypeSet(uint256 creditTypeId, bool state);
    event GFlyPerCreditSet(uint256 amount);
    event MagicPerCreditSet(uint256 amount);
    event TreasuresPerCreditSet(uint256 amount);
    event MagicForLPWithdrawn(uint256 amount);
    event GFlyForLPWithdrawn(uint256 amount);
    event MagicForLPAdded(uint256 amount);
    event GFlyForLPAdded(uint256 amount);
    event LiquidityAdded(uint56 liquidity, uint256 providedMagic, uint256 providedGFly);

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
     * @dev Sets the amount of Magic to be used when creating a credit
     */
    function setMagicPerCredit(uint256 amount) external onlyOwner {
        gs().magicPerCredit = amount;
        emit MagicPerCreditSet(amount);
    }

    /**
     * @dev Sets the amount of Treasures to be used when creating a credit
     */
    function setTreasuresPerCredit(uint256 amount) external onlyOwner {
        gs().treasuresPerCredit = amount;
        emit TreasuresPerCreditSet(amount);
    }

    /**
     * @dev Removes Magic reserved for automatic LP providing
     */
    function removeMagicForLp(uint256 amount) external onlyOwner {
        if (amount > gs().magicForLp) revert Errors.InsufficientMagicForLpAmount();
        gs().magicForLp -= amount;
        IERC20(gs().magic).transfer(msg.sender, amount);
        emit MagicForLPWithdrawn(amount);
    }

    /**
     * @dev Removes gFLY reserved for automatic LP providing
     */
    function removeGFlyForLp(uint256 amount) external onlyOwner {
        if (amount > gs().gFlyForLp) revert Errors.InsufficientGFlyForLpAmount();
        gs().gFlyForLp -= amount;
        IERC20(gs().gFLY).transfer(msg.sender, amount);
        emit GFlyForLPWithdrawn(amount);
    }

    /**
     * @dev Adds magic reserved for automatic LP providing
     */
    function addMagicForLp(uint256 amount) external {
        IERC20(gs().magic).transferFrom(msg.sender, address(this), amount);
        gs().magicForLp += amount;
        emit MagicForLPAdded(amount);
    }

    /**
     * @dev Adds gFLY reserved for automatic LP providing
     */
    function addGFlyForLp(uint256 amount) external {
        IERC20(gs().gFLY).transferFrom(msg.sender, address(this), amount);
        gs().gFlyForLp += amount;
        emit GFlyForLPAdded(amount);
    }

    /**
     * @dev Sets the Magic/gFLY LP receiver address
     */
    function setLpReceiver(address lpReceiver) external onlyOwner {
        if (lpReceiver == address(0)) revert Errors.InvalidAddress();
        gs().lpReceiver = lpReceiver;
    }

    /**
     * @dev Sets the gFLY treshold for LP swaps
     */
    function setgFlyLpTreshold(uint256 gFlyLpTreshold) external onlyOwner {
        gs().gFlyLpTreshold = gFlyLpTreshold;
    }

    /**
     * @dev Sets the Magic treshold for LP swaps
     */
    function setMagicLpTreshold(uint256 magicLpTreshold) external onlyOwner {
        gs().magicLpTreshold = magicLpTreshold;
    }

    /**
     * @dev Sets the BPS denominator
     */
    function setBPSDenominator(uint256 bpsDenominator) external onlyOwner {
        gs().bpsDenominator = bpsDenominator;
    }

    /**
     * @dev Sets the slippage in BPS
     */
    function setSlippageInBPS(uint256 slippageInBPS) external onlyOwner {
        gs().slippageInBPS = slippageInBPS;
    }

    /**
     * @dev Automatically swap Magic and gFLY into LP tokens if the Magic and/or gFLY tresholds are reached.
     * LP tokens are sent to the LP Receiver address
     */
    function swapToLP() external onlyBattleflyBot {
        LibCreditUtils.swapToLP();
    }
}

