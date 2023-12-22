/**
 * State for the vault
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// ===============
//    IMPORTS
// ===============
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import "./VM.sol";
import "./storage_AccessControl.sol";
import "./OperationsQueue.sol";

import "./vm_Constants.sol";
import "./ITokenStash.sol";
import "./VaultUtilities.sol";

contract VaultState is AccessControl {
    // =====================
    //      CONSTRUCTOR
    // =====================
    /**
     * @notice
     * The constructor,
     * accepts all of the different configs for this strategy contract
     * @param steps - A linked list of YCStep. a YCStep specifies the encoded FunctionCall of a step,
     * the indexes of it's children within the array, and an optional array of "conditions".
     * In which case it means the step is a conditional block.
     * @param seedSteps - A linked list of YCStep like the above, this time,
     * for the seed strategy (i.e, the strategy that runs on deposit)
     * @param uprootSteps - Another linked list of YCStep,
     * but for the "Uprooting" strategy (the reverse version of the strategy)
     * @param approvalPairs - A 2D array of addresses -
     * at index 0 there is an ERC20-compatible token contract address, and at index 1 there is a
     * contract address to approve. This is in order to iterate over and pre-approve all addresses required.
     * @param depositToken - The token of this vault that users deposit into here, as an address
     *
     * @param ispublic - Whether the vault is publicly accessible or not
     */
    constructor(
        bytes[] memory seedSteps,
        bytes[] memory steps,
        bytes[] memory uprootSteps,
        address[2][] memory approvalPairs,
        IERC20 depositToken,
        bool ispublic,
        address creator
    ) AccessControl(creator, msg.sender) {
        /**
         * @dev We set the immutable set of steps, seed steps, and uproot steps
         */
        STEPS = steps;
        SEED_STEPS = seedSteps;
        UPROOTING_STEPS = uprootSteps;

        /**
         * @dev We set the depositToken immutable variable
         */
        DEPOSIT_TOKEN = depositToken;

        /**
         * @dev
         * We set the vault's initial privacy
         */
        isPublic = ispublic;

        /**
         * @dev We iterate over each approval pair and approve them as needed.
         */
        for (uint256 i = 0; i < approvalPairs.length; i++) {
            address addressToApprove = approvalPairs[i][1];
            addressToApprove = addressToApprove == address(0)
                ? msg.sender // The diamond
                : addressToApprove;

            IERC20(approvalPairs[i][0]).approve(
                addressToApprove,
                type(uint256).max
            );
        }

        /**
         * @dev We also add mods and admin permission to the creator
         */
        admins[creator] = true;
        mods[creator] = true;
        whitelistedUsers[creator] = true;
    }

    // =====================
    //      IMMUTABLES
    // =====================

    /**
     * @dev The deposit token of the vault
     */
    IERC20 public immutable DEPOSIT_TOKEN;

    /**
     * @notice
     * @dev
     * A linked list containing the tree of (encoded) steps to execute on the main triggers
     */
    bytes[] internal STEPS;

    /**
     * @dev Just as the above -
     * A linked list of encoded steps, but for the seed strategy (runs on deposit, i.e initial allocations)
     */
    bytes[] internal SEED_STEPS;

    /**
     * @dev Another linked list of steps,
     * but for the "uprooting" strategy (A "reverse" version of the strategy, executed on withdrawals)
     */
    bytes[] internal UPROOTING_STEPS;

    /**
     * @notice @dev
     * Used in offchain simulations when hydrating calldata
     */
    bool isMainnet = true;

    // ==============================
    //           STORAGE
    // ==============================
    /**
     * @notice
     * The total amount of shares of this vault, directly correlated with deposit tokens
     * 1 token deposited += totalShares(1)
     * 1 token withdrawan -= totalShares(1)
     */
    uint256 public totalShares;

    /**
     * @notice
     * Mapping user addresses to their corresponding balances of vault shares
     */
    mapping(address => uint256) public balances;

    /**
     * @notice
     * Active share percentage,
     * used to track withdrawals incase of an offchain execution required mid way
     */
    uint256 activeShare;

    /**
     * @notice
     * @dev
     * We keep track of the approximate gas required to execute withdraw and deposit operations.
     * This is in order to charge users for the gas they are going to cost the executor
     * after their offchain hydration.
     *
     * We also keep track of the gas for the strategy run operation, mainly for analytical purposes, tho.
     */
    uint256 public approxWithdrawalGas = 0.001 ether;

    uint256 public approxDepositGas = 0.001 ether;

    uint256 public approxStrategyGas = 0.001 ether;

    /**
     * @dev This state variable indiciates whether we are locked or not,
     * this is used by the offchain in order to not process additional requests until
     * we are unlocked
     */
    bool locked;

    // =====================
    //        GETTERS
    // =====================
    function getVirtualStepsTree(
        ExecutionTypes executionType
    ) public view returns (bytes[] memory) {
        if (executionType == ExecutionTypes.SEED) return SEED_STEPS;
        if (executionType == ExecutionTypes.TREE) return STEPS;
        if (executionType == ExecutionTypes.UPROOT) return UPROOTING_STEPS;
        revert();
    }
}

