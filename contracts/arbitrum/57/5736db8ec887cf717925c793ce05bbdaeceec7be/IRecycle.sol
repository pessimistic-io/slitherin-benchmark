// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.18;

/*
 * @title IRecycle Interface
 *
 * @notice Interface for recycling and distributing assets within a contract.
 *
 * Co-Founders:
 * - Simran Dhillon: simran@xenify.io
 * - Hardev Dhillon: hardev@xenify.io
 * - Dayana Plaz: dayana@xenify.io
 *
 * Official Links:
 * - Twitter: https://twitter.com/xenify_io
 * - Telegram: https://t.me/xenify_io
 * - Website: https://xenify.io
 *
 * Disclaimer:
 * This contract aligns with the principles of the Fair Crypto Foundation, promoting self-custody, transparency, consensus-based
 * trust, and permissionless value exchange. There are no administrative access keys, underscoring our commitment to decentralization.
 * Engaging with this contract involves technical and legal risks. Users must conduct their own due diligence and ensure compliance
 * with local laws and regulations. The software is provided "AS-IS," without warranties, and the co-founders and developers disclaim
 * all liability for any vulnerabilities, exploits, errors, or breaches that may occur. By using this contract, users accept all associated
 * risks and this disclaimer. The co-founders, developers, or related parties will not bear liability for any consequences of non-compliance.
 *
 * Redistribution and Use:
 * Redistribution, modification, or repurposing of this contract, in whole or in part, is strictly prohibited without express written
 * approval from all co-founders. Approval requests must be sent to the official email addresses of the co-founders, ensuring responses
 * are received directly from these addresses. Proposals for redistribution, modification, or repurposing must include a detailed explanation
 * of the intended changes or uses and the reasons behind them. The co-founders reserve the right to request additional information or
 * clarification as necessary. Approval is at the sole discretion of the co-founders and may be subject to conditions to uphold the
 * project’s integrity and the values of the Fair Crypto Foundation. Failure to obtain express written approval prior to any redistribution,
 * modification, or repurposing will result in a breach of these terms and immediate legal action.
 *
 * Copyright and License:
 * Copyright © 2023 Xenify (Simran Dhillon, Hardev Dhillon, Dayana Plaz). All rights reserved.
 * This software is provided 'as is' and may be used by the recipient. No permission is granted for redistribution,
 * modification, or repurposing of this contract. Any use beyond the scope defined herein may be subject to legal action.
 */
interface IRecycle {

    /// -------------------------------------- ERRORS --------------------------------------- \\\

    /**
     * @notice Error thrown when the transfer of native tokens failed.
     */
    error TransferFailed();

    /**
     * @notice Error thrown when an invalid address is provided.
     */
    error InvalidAddress();

    /**
     * @notice Error thrown when the provided native token amount is zero.
     */
    error ZeroNativeAmount();

    /**
     * @notice Error thrown when the caller is not authorized.
     */
    error UnauthorizedCaller();

    /**
     * @notice Error thrown when fees has been collected for current cycle.
     */
    error FeeCollected(uint256 lastClaimCycle);

    /**
     * @notice Error thrown when the contract is already initialised.
     */
    error ContractInitialised(address contractAddress);

    /// -------------------------------------- EVENTS --------------------------------------- \\\

    /**
     * @notice Emitted when native tokens are converted (recycled) into other tokens.
     * @param user Address of the user who initiated the recycle action.
     * @param nativeAmount Amount of native tokens recycled.
     */
    event RecycleAction(
        address indexed user,
        uint256 nativeAmount
    );

    /// ------------------------------------------------------------------------------------- \\\

    /**
     * @notice Emitted when the protocol performs a buyback and then burns the purchased tokens.
     * @dev This event is used to log the successful execution of the buyback and burn operation.
     * It should be emitted after the protocol has used native tokens to buy back its own tokens
     * from the open market and subsequently burned them, effectively reducing the total supply.
     * The amount represents the native tokens spent in the buyback process before the burn.
     * @param creator Address of the entity or contract that initiated the buyback and burn.
     * @param amount The amount of native tokens used for the buyback operation.
     */
    event BuybackBurnAction(
        address indexed creator,
        uint256 amount
    );

    /// --------------------------------- EXTERNAL FUNCTIONS -------------------------------- \\\

    /**
     * @notice Collects fees for protocol owned liquidity.
     * @dev Implementing contracts should specify the mechanism for collecting fees.
     */
    function collectFees() external;

    /// ------------------------------------------------------------------------------------- \\\

    /**
     * @notice Recycles assets held within the contract.
     * @dev Implementing contracts should detail the recycling mechanism.
     * If the function is intended to handle Ether, it should be marked as payable.
     */
    function recycle() external payable;

    /// ------------------------------------------------------------------------------------- \\\

    /**
     * @notice Sets the token ID for internal reference.
     * @dev Implementing contracts should specify how this ID is used within the protocol.
     */
    function setTokenId(uint256) external;

    /// ------------------------------------------------------------------------------------- \\\

    /**
     * @notice Executes a buyback, burning XNF tokens and distributing native tokens to the team.
     * @dev Swaps 50% of the sent value for XNF, burns it, and sends 10% to the team. The function
     * is non-reentrant and must have enough native balance to execute the swap and burn.
     */
    function executeBuybackBurn() external payable;

    /// ------------------------------------------------------------------------------------- \\\

    /**
     * @notice Executes a swap from XNF to native tokens (e.g., ETH), with a guaranteed minimum output.
     * @dev Swaps XNF for native tokens using swapRouter, transferring the output directly to the caller. A deadline for
     * the swap can be specified which is the timestamp after which the transaction is considered invalid. Before execution,
     * ensure swapRouter is secure and 'amountOutMinimum' accounts for slippage. The 'deadline' should be carefully set to allow
     * sufficient time for the transaction to be mined while protecting against market volatility.
     * @param amountIn The amount of XNF tokens to swap.
     * @param amountOut The minimum acceptable amount of native tokens in return.
     * @param deadline The timestamp by which the swap must be completed.
     */
    function swapXNF(uint256 amountIn, uint256 amountOut, uint256 deadline) external;

    /// ------------------------------------------------------------------------------------- \\\
}
