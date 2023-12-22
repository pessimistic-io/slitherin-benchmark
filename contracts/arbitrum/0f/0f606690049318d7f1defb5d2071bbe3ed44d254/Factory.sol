/**
 * Used to create & manage strategy vaults
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./Vault.sol";
import "./Strategies.sol";
import "./Users.sol";
import {IERC20} from "./IERC20.sol";
// import "../triggers/Registry.sol";
import "./storage_TriggersManager.sol";
import "./Modifiers.sol";

contract FactoryFacet is Modifiers {
    // ==================
    //      EVENTS
    // ==================
    /**
     * Deployed on strategy deployment
     */
    event VaultCreated(
        address indexed strategyAddress,
        address indexed creator,
        address indexed depositToken,
        bytes constructorArgs
    );

    // ==================
    //     MODIFIERS
    // ==================
    /**
     * Asserts that an inputted address must be a premium user, if an inputted
     * boolean is "false" (if a vault is private)
     */
    modifier noPrivacyForTheWicked(bool isPublic, address requester) {
        require(
            isPublic || UsersStorageLib.getUsersStorage().isPremium[requester],
            "No Privacy For The Wicked"
        );
        _;
    }

    // ==================
    //     METHODS
    // ==================
    /**
     * @notice
     * Create & Deploy A Vault
     * @param seedSteps - The seed steps that run on a deposit trigger
     * @param treeSteps - The tree of steps that run on any of the strategy's triggers
     * @param uprootSteps - The uproot steps that run on a withdrawal trigger
     * @param approvalPairs - A 2D array of [ERC20Token, addressToApprove]. Which will be approved on deployment of the vault
     * @param depositToken - An IERC20 token which is used for deposits into the vault
     * @param isPublic - The visibility/privacy of this vault. Private only allowed for premium users!!
     */
    function createVault(
        bytes[] memory seedSteps,
        bytes[] memory treeSteps,
        bytes[] memory uprootSteps,
        address[2][] memory approvalPairs,
        Trigger[] memory triggers,
        IERC20 depositToken,
        bool isPublic
    )
        external
        noPrivacyForTheWicked(isPublic, msg.sender)
        returns (Vault createdVault)
    {
        /**
         * Assert that the triggers & triggers settings lengths math
         */

        /**
         * Begin by deploying the vault contract (With the msg.sender of this call as the creator)
         */
        createdVault = new Vault(
            seedSteps,
            treeSteps,
            uprootSteps,
            approvalPairs,
            depositToken,
            isPublic,
            msg.sender
        );

        /**
         * Push the strategy to the storage array
         */
        StrategiesStorageLib.getStrategiesStorage().strategies.push(
            createdVault
        );

        StrategiesStorageLib.getStrategiesStorage().strategiesState[
                createdVault
            ] = StrategyState(true, 0);

        // Register all of the triggers for the strategy
        TriggersManagerFacet(address(this)).registerTriggers(
            triggers,
            createdVault
        );

        emit VaultCreated(
            address(createdVault),
            msg.sender,
            address(depositToken),
            abi.encode(
                seedSteps,
                treeSteps,
                uprootSteps,
                approvalPairs,
                depositToken,
                isPublic,
                msg.sender
            )
        );
    }
}

