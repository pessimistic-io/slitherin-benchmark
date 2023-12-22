// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.18;

import {ILayerZeroReceiver} from "./ILayerZeroReceiver.sol";
import {IWormholeReceiver} from "./IWormholeReceiver.sol";
import {IWormholeRelayer} from "./IWormholeRelayer.sol";

/*
 * @title YSL interface
 *
 * @notice This interface outlines functions for the YSL token, which is an ERC20 token with additional
 * functionality for bridging and burning.
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
interface IYSL
{
    /// -------------------------------------- ERRORS --------------------------------------- \\\

    /**
     * @notice This error is thrown when an invalid claim proof is provided.
     */
    error InvalidClaimProof();

    /**
     * @notice This error is thrown when the claim period has expired.
     */
    error ClaimPeriodExpired();

    /**
     * @notice This error is thrown when an airdrop has already been claimed.
     */
    error AirdropAlreadyClaimed();

    /// -------------------------------------- EVENTS --------------------------------------- \\\

    /**
     * @notice Emitted when a user successfully claims their airdrop.
     * @param user Address of the user claiming the airdrop.
     * @param amount Amount of YSL claimed.
     */
    event Airdropped(
        address indexed user,
        uint256 amount
    );

    /// --------------------------------- EXTERNAL FUNCTIONS -------------------------------- \\\

    /**
     * @notice Burns a specified amount of tokens from a user's address.
     * @dev Only addresses with the required allowance can burn tokens on behalf of a user.
     * @param _user Address from which tokens will be burned.
     * @param _amount Amount of tokens to burn.
     */
    function burn(
        address _user,
        uint256 _amount
    ) external;

    /// ------------------------------------------------------------------------------------- \\\

    /**
     * @notice Allows users to claim their airdropped tokens using a Merkle proof.
     * @dev Verifies the Merkle proof against the stored Merkle root and mints the claimed amount to the user.
     * @param proof Array of bytes32 values representing the Merkle proof.
     * @param account Address of the user claiming the airdrop.
     * @param amount Amount of tokens being claimed.
     */
    function claim(
        bytes32[] calldata proof,
        address account,
        uint256 amount
    ) external;

    /// ------------------------------------------------------------------------------------- \\\
}
