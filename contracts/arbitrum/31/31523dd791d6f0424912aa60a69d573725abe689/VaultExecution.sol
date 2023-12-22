/**
 * The execution functions for the vault (Internal/Used by YC Diamond)
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// ===============
//    IMPORTS
// ===============
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import "./VM.sol";
import "./State.sol";
import "./vm_Constants.sol";
import "./VaultUtilities.sol";
import "./IAccessControl.sol";
import "./automation_Types.sol";
import "./console.sol";

abstract contract VaultExecution is
    YCVM,
    VaultUtilities,
    VaultConstants,
    VaultState
{
    // ===========
    //    LIBS
    // ===========
    using SafeERC20 for IERC20;

    // =================
    //      METHODS
    // =================
    /**
     * @notice
     * executeDeposit()
     * The actual deposit logic
     * @param response - Optional response from OffchainLookup
     * @param encodedDepositData - Encoded DepositData struct, set as extraData in offchain lookups
     */
    function executeDeposit(
        bytes memory response,
        bytes memory encodedDepositData
    ) external onlyWhitelistedOrPublicVault {
        _executeDeposit(response, encodedDepositData);
    }

    function _executeDeposit(
        bytes memory response,
        bytes memory encodedDepositData
    ) internal {
        DepositData memory depositData = abi.decode(
            encodedDepositData,
            (DepositData)
        );

        uint256 amount = depositData.amount;

        if (DEPOSIT_TOKEN.allowance(msg.sender, address(this)) < amount)
            revert InsufficientAllowance();

        // Transfer to us
        DEPOSIT_TOKEN.safeTransferFrom(msg.sender, address(this), amount);

        // Increment total shares supply & user's balance
        totalShares += amount;
        balances[msg.sender] += amount;

        assembly {
            // We MSTORE at the deposit amount memory location the deposit amount
            // (may be accessed by commands to determine amount arguments)
            mstore(DEPOSIT_AMT_MEM_LOCATION, amount)
        }

        bytes[] memory cachedOffchainCommands = abi.decode(response, (bytes[]));

        executeStepTree(
            SEED_STEPS,
            cachedOffchainCommands,
            new uint256[](1),
            VaultExecution.executeDeposit.selector,
            encodedDepositData
        );
    }

    /**
     * @notice
     * executeWithdraw()
     * The actual withdraw logic
     * @param response - Optional response from OffchainLookup
     * @param encodedWithdrawalData - Encoded WithdrawalData struct, set as extraData in offchain lookups
     */
    function executeWithdrawal(
        bytes calldata response,
        bytes calldata encodedWithdrawalData
    ) external onlyWhitelistedOrPublicVault {
        _executeWithdrawal(response, encodedWithdrawalData);
    }

    function _executeWithdrawal(
        bytes memory response,
        bytes memory encodedWithdrawalData
    ) internal {
        WithdrawalData memory withdrawalData = abi.decode(
            encodedWithdrawalData,
            (WithdrawalData)
        );

        uint256 amount = withdrawalData.amount;

        if (amount > balances[msg.sender]) revert InsufficientShares();

        balances[msg.sender] -= amount;
        totalShares -= amount;

        uint256 shareOfVaultInPercentage = (totalShares + amount) / amount;

        assembly {
            // We MSTORE at the withdraw share memory location the % share of the withdraw amount of the total vault, times 100
            // (e.g, 100 shares to withdraw, 1000 total shares = 1000 / 100 * 100(%) = 1000 (10% multipled by 100, for safe maths...))
            mstore(
                WITHDRAW_SHARES_MEM_LOCATION,
                mul(shareOfVaultInPercentage, 100)
            )
        }

        uint256 preVaultBalance = DEPOSIT_TOKEN.balanceOf(address(this));

        bytes[] memory cachedOffchainCommands = abi.decode(response, (bytes[]));

        executeStepTree(
            UPROOTING_STEPS,
            cachedOffchainCommands,
            new uint256[](1),
            VaultExecution.executeWithdrawal.selector,
            encodedWithdrawalData
        );

        uint256 debt = DEPOSIT_TOKEN.balanceOf(address(this)) - preVaultBalance;

        DEPOSIT_TOKEN.safeTransfer(msg.sender, debt);
    }

    /**
     * Execute strategy
     */
    function executeStrategy(
        bytes calldata response,
        bytes calldata extraData
    ) external onlyDiamond {
        _executeStrategy(response, extraData);
    }

    function _executeStrategy(
        bytes memory response,
        bytes memory extraData
    ) internal {
        bytes[] memory cachedOffchainCommands = abi.decode(response, (bytes[]));

        executeStepTree(
            STEPS,
            cachedOffchainCommands,
            new uint256[](1),
            VaultExecution.executeStrategy.selector,
            extraData
        );
    }

    // ========================
    //     INTERNAL METHODS
    // ========================
    /**
     * @notice
     * executeStepTree()
     * Accepts a linked-list (array) of YCStep, and a starting index to begin executing.
     * Note this function is recursive - It executes a step, then all of it's children, then all of their children, etc.
     *
     * @param virtualTree - A linked list array of YCSteps to execute
     * @param startingIndices - An array of indicies of the steps to begin executing the tree from
     */
    function executeStepTree(
        bytes[] memory virtualTree,
        bytes[] memory cachedOffchainCommands,
        uint256[] memory startingIndices,
        bytes4 callbackFunction,
        bytes memory actionContext
    ) internal {
        /**
         * Iterate over each one of the starting indices
         */
        for (uint256 i = 0; i < startingIndices.length; i++) {
            uint256 stepIndex = startingIndices[i];

            YCStep memory step = abi.decode(virtualTree[stepIndex], (YCStep));

            /**
             * We first check to see if this step is a callback step.
             */
            if (step.isCallback) {
                // If already got the command, run it
                if (
                    cachedOffchainCommands.length > stepIndex &&
                    bytes32(cachedOffchainCommands[stepIndex]) != bytes32(0)
                )
                    _runFunction(cachedOffchainCommands[stepIndex]);

                    // Revert with OffchainLookup, CCIP read will fetch from corresponding Offchain Action.
                else
                    _requestOffchainLookup(
                        step,
                        stepIndex,
                        cachedOffchainCommands,
                        callbackFunction,
                        actionContext
                    );
            } else if (bytes32(step.func) != bytes32(0))
                _runFunction(step.func);

            executeStepTree(
                virtualTree,
                cachedOffchainCommands,
                step.childrenIndices,
                callbackFunction,
                actionContext
            );
        }
    }

    /**
     * Send a CCIP OffchainLookup request to get a step's data
     * @param step - The original step
     * @param idx - The index of that step
     * @param cachedOffchainCommands - Commands that were already returned by offchain
     * @param callbackSelector - The selector of the function to callback with the new data
     * @param actionContext - ExtraData passed by the action
     */
    function _requestOffchainLookup(
        YCStep memory step,
        uint256 idx,
        bytes[] memory cachedOffchainCommands,
        bytes4 callbackSelector,
        bytes memory actionContext
    ) internal {
        (bytes memory nakedFunc, , ) = _separateCommand(step.func);

        FunctionCall memory originalCall = abi.decode(
            nakedFunc,
            (FunctionCall)
        );

        bytes memory interpretedArgs = interpretCommandsAndEncodeChunck(
            originalCall.args
        );

        string memory offchainActionsUrl = IAccessControlFacet(
            address(YC_DIAMOND)
        ).getOffchainActionsUrl();

        string[] memory urls = new string[](1);
        urls[0] = offchainActionsUrl;

        OffchainActionRequest memory offchainRequest = OffchainActionRequest(
            address(this),
            block.chainid,
            idx,
            cachedOffchainCommands,
            originalCall.target_address,
            originalCall.signature,
            interpretedArgs
        );

        revert OffchainLookup(
            address(this),
            urls,
            abi.encode(offchainRequest),
            callbackSelector,
            actionContext
        );
    }
}

