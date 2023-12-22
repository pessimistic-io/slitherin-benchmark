/**
 * Used to create & manage strategy vaults
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./Vault.sol";
import "./Strategies.sol";
import "./Users.sol";
import "./ERC20.sol";
import "./Registry.sol";
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
        address indexed depositToken
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
    //     GETTERS
    // ==================
    function getStrategiesList()
        external
        view
        returns (Vault[] memory strategies)
    {
        strategies = StrategiesStorageLib.getStrategiesStorage().strategies;
    }

    function getStrategyState(
        Vault strategy
    ) external view returns (StrategyState memory strategyState) {
        strategyState = StrategiesStorageLib
            .getStrategiesStorage()
            .strategiesState[strategy];
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
    // 
     * @param approvalPairs - A 2D array of [ERC20Token, addressToApprove]. Which will be approved on deployment of the vault
     * @param depositToken - An ERC20 token which is used for deposits into the vault
     * @param isPublic - The visibility/privacy of this vault. Private only allowed for premium users!!

     */
    function createVault(
        bytes[] memory seedSteps,
        bytes[] memory treeSteps,
        bytes[] memory uprootSteps,
        address[2][] memory approvalPairs,
        ERC20 depositToken,
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

        emit VaultCreated(
            address(createdVault),
            msg.sender,
            address(depositToken)
        );
        /**
         * Finally, we move onto registering each one of the triggers on the Registry facet.
         * The Registry facet will register it on the corresponding trigger-specific facet,
         * and on the strategy's mapping in the general storage, where we store an array of the registered triggers.
         */
     
    }

    /**
     * @notice
     * Fund a vault's native gas balance
     * @param strategyAddress - Address of the strategy to fund
     */
    function fundGasBalance(address strategyAddress) public payable {
        /**
         * Shorthand for strategies storage
         */
        StrategiesStorage storage strategiesStorage = StrategiesStorageLib
            .getStrategiesStorage();
        /**
         * Storage ref to our strategy in the mapping
         */
        StrategyState storage strategy = strategiesStorage.strategiesState[
            Vault(strategyAddress)
        ];

        /**
         * Require the strategy to exist
         */
        require(strategy.registered, "Vault Does Not Exist");

        /**
         * Finally, increment the gas balance in the amount provided
         */
        strategy.gasBalanceWei += msg.value;
    }

    /**
     * @notice
     * deductAndTransferVaultGas()
     * Deduct from a vault's gas balance, and transfer it to some address
     * can only be called internally!!
     * @param strategy - Address of the strategy to deduct
     * @param receiver - The address of the Ether receiver
     * @param debtInWei - The debt of the strategy in WEI (not GWEI!!) to deduct
     */
    function deductAndTransferVaultGas(
        Vault strategy,
        address payable receiver,
        uint256 debtInWei
    ) public onlySelf {
        // Shorthand for strategies storage

        StrategiesStorage storage strategiesStorage = StrategiesStorageLib
            .getStrategiesStorage();

        // Storage ref to our strategy in the mapping
        StrategyState storage strategyState = strategiesStorage.strategiesState[
            strategy
        ];

        // Assert that the balance is sufficient and deduct the debt
        require(
            strategyState.gasBalanceWei >= debtInWei,
            "Insufficient Gas Balance To Deduct."
        );

        // Deduct it
        strategyState.gasBalanceWei -= debtInWei;

        // Transfer to the receiver
        receiver.transfer(debtInWei);
    }
}

