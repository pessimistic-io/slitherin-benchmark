/**
 * The registry for triggers on strategies
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./Vault.sol";
import "./Strategies.sol";

contract Registry {
    /**
     * Register a trigger on a strategy
     * @param strategy - The strategy vault to register the trigger on
     * @param trigger - The type of trigger to register (Triggers enum)
     * @param triggerSettings - Arbitrary bytes. The settings to pass on to the specific trigger registry (decoding is up to it)
     */
    function registerTrigger(
        Vault strategy,
        Triggers trigger,
        bytes memory triggerSettings
    ) public view {
        /**
         * @notice
         * We make a switch case per trigger case and call it's specific registry,
         *  with the provided setting
         */
        if (trigger == Triggers.AUTOMATION) {
            strategy;
            triggerSettings;
        }
        address(this);
    }
}

