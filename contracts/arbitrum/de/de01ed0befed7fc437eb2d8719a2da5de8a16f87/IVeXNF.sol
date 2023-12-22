// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.18;

/*
 * @title IVeXNF Interface
 *
 * @notice Interface for querying "time-weighted" supply and balance of NFTs.
 * Provides methods to determine the total supply and user balance at specific points in time.
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
interface IVeXNF {

    /// --------------------------------- EXTERNAL FUNCTIONS -------------------------------- \\\

    /**
     * @notice Merges all NFTs that user has into a single new NFT with 1 year lock period.
     */
    function mergeAll() external;

    /// ------------------------------------------------------------------------------------- \\\

    /**
     * @notice Records a global checkpoint for data tracking.
     */
    function checkpoint() external;

    /// ------------------------------------------------------------------------------------- \\\

    /**
     * @notice Withdraws all tokens from all expired NFT locks.
     */
    function withdrawAll() external;

    /// ------------------------------------------------------------------------------------- \\\

    /**
     * @notice Withdraws all tokens from an expired NFT lock.
     */
    function withdraw(uint) external;

    /// ------------------------------------------------------------------------------------- \\\

    /**
     * @notice Merges multiple NFTs into a single new NFT.
     */
    function merge(uint[] memory) external;

    /// ------------------------------------------------------------------------------------- \\\

    /**
     * @notice Deposits tokens into a specific NFT lock.
     */
    function depositFor(uint, uint) external;

    /// ------------------------------------------------------------------------------------- \\\

    /**
     * @notice Splits a single NFT into multiple new NFTs with specified amounts.
     */
    function split(uint[] calldata, uint) external;

    /// ------------------------------------------------------------------------------------- \\\

    /**
     * @notice Extends the unlock time of a specific NFT lock.
     */
    function increaseUnlockTime(uint, uint) external;

    /// ------------------------------------------------------------------------------------- \\\

    /**
     * @notice Retrieves the current total supply of tokens.
     * @return The current total token supply.
     */
    function totalSupply() external view returns (uint);

    /// ------------------------------------------------------------------------------------- \\\

    /**
     * @notice Retrieves the end timestamp of a lock for a specific NFT.
     * @return The timestamp when the NFT's lock expires.
     */
    function lockedEnd(uint) external view returns (uint);

    /// ------------------------------------------------------------------------------------- \\\

    /**
     * @notice Creates a lock for a user for a specified amount and duration.
     * @return tokenId The identifier of the newly created NFT.
     */
    function createLock(uint, uint) external returns (uint);

    /// ------------------------------------------------------------------------------------- \\\

    /**
     * @notice Calculates the total voting power at a specific timestamp.
     * @return The total voting power at the specified timestamp.
     */
    function totalSupplyAtT(uint) external view returns (uint);

    /// ------------------------------------------------------------------------------------- \\\

    /**
     * @notice Retrieves the balance of a specific NFT at a given timestamp.
     * @return The balance of the NFT at the given timestamp.
     */
    function balanceOfNFTAt(uint, uint) external view returns (uint);

    /// ------------------------------------------------------------------------------------- \\\

    /**
     * @notice Retrieves the total token supply at a specific timestamp.
     * @return The total token supply at the given timestamp.
     */
    function getPastTotalSupply(uint256) external view returns (uint);

    /// ------------------------------------------------------------------------------------- \\\

    /**
     * @notice Retrieves the most recent voting power decrease rate for a specific NFT.
     * @return The slope value representing the rate of voting power decrease.
     */
    function get_last_user_slope(uint) external view returns (int128);

    /// ------------------------------------------------------------------------------------- \\\

    /**
     * @notice Creates a new NFT lock for a specified address, locking a specific amount of tokens.
     * @return tokenId The identifier of the newly created NFT.
     */
    function createLockFor(uint, uint, address) external returns (uint);

    /// ------------------------------------------------------------------------------------- \\\

     /**
     * @notice Retrieves a list of NFT IDs owned by a specific address.
     * @return An array of NFT IDs owned by the specified address.
     */
    function userToIds(address) external view returns (uint256[] memory);

    /// ------------------------------------------------------------------------------------- \\\

    /**
     * @notice Retrieves the timestamp of a specific checkpoint for an NFT.
     * @return The timestamp of the specified checkpoint.
     */
    function userPointHistory_ts(uint, uint) external view returns (uint);

    /// ------------------------------------------------------------------------------------- \\\

    /**
     * @notice Checks if an address is approved to manage a specific NFT or if it's the owner.
     * @return True if the address is approved or is the owner, false otherwise.
     */
    function isApprovedOrOwner(address, uint) external view returns (bool);

    /// ------------------------------------------------------------------------------------- \\\

    /**
     * @notice Retrieves the aggregate balance of NFTs owned by a specific user at a given epoch time.
     * @return totalBalance The total balance of the user's NFTs at the given timestamp.
     */
    function totalBalanceOfNFTAt(address, uint) external view returns (uint256);

    /// ------------------------------------------------------------------------------------- \\\
}
