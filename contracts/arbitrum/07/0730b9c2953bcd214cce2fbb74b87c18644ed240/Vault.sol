// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// ===============
//    IMPORTS
// ===============
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import "./VaultExecution.sol";

/**
 * The part of the vault contract containing various
 * state (storage) variables and immutables.
 *
 * This is the root contract being inherited
 */

contract Vault is VaultExecution {
    // LIBS
    using SafeERC20 for IERC20;

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
    )
        VaultState(
            seedSteps,
            steps,
            uprootSteps,
            approvalPairs,
            depositToken,
            ispublic,
            creator
        )
    {}

    // ==============================
    //     PUBLIC VAULT METHODS
    // ==============================

    /**
     * @notice
     * Request A Deposit Into The Vault
     * @param amount - The amount of the deposit token to deposit
     */
    function deposit(
        uint256 amount
    ) external payable onlyWhitelistedOrPublicVault {
        // Reserve first memory spot for some value (e.g deposit amount)
        assembly {
            mstore(0x40, add(mload(0x40), 0x20))
        }
        _executeDeposit(
            abi.encode(new bytes[](0)),
            abi.encode(DepositData(amount))
        );
    }

    /**
     * @notice
     * Request to withdraw out of the vault
     * @param amount - the amount of shares to withdraw
     */
    function withdraw(
        uint256 amount
    ) external payable onlyWhitelistedOrPublicVault {
        // Reserve first memory spot for some value (e.g withdrawal % share)
        assembly {
            mstore(0x40, add(mload(0x40), 0x20))
        }
        _executeWithdrawal(
            abi.encode(new bytes[](0)),
            abi.encode(WithdrawalData(amount))
        );
    }

    /**
     * @notice
     * runStrategy()
     * Requests a strategy execution operation,
     * only called by the diamond (i.e from an executor on the diamond)
     */
    function runStrategy() external onlyDiamond {
        // Reserve first memory spot for some value (e.g deposit amount)
        assembly {
            mstore(0x40, add(mload(0x40), 0x20))
        }
        _executeStrategy(abi.encode(new bytes[](0)), new bytes(0));
    }

    /**
     * @notice
     * @dev
     * Only called by Diamond.
     * Internal approval - Used by utility/adapter facets to approve tokens
     * on our behalf, to the diamond (only!), that we could not pre-approve in advanced.
     * Things like LP tokens that may not be known pre-deployment, may require runtime approvals.
     * We of course only allow this to be on the Diamond itself - So anything that wants to implement this
     * must be a facet on the Diamond itself, which is more secure.
     * @param token - Token to approve
     * @param amt - Amount to approve
     */
    function approveDaddyDiamond(
        address token,
        uint256 amt
    ) external onlyDiamond {
        // Cheaper to read msg.sender than YC_DIAMOND, we know it's only the Diamond already here
        IERC20(token).approve(msg.sender, amt);
    }
}

