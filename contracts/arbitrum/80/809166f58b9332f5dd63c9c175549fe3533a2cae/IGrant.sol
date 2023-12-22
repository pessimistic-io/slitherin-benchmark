// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {ITerm, IAgreementManager} from "./ITerm.sol";

import {IERC20} from "./IERC20.sol";

/// @notice Agreement Term holds tokens claimable by the agreement owner.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/terms/IGrant.sol)
interface IGrant is ITerm {
    /// @dev Data structure for Grant properties
    struct GrantData {
        // Granted token contract address
        IERC20 token;
        // Amount of tokens granted
        uint256 amount;
    }

    error Grant__InsufficientClaimable();

    event Claimed(IAgreementManager indexed manager, uint256 indexed tokenId, uint256 amount);

    function tokenBalance(IAgreementManager manager, uint256 tokenId) external view returns (uint256);

    /**
     * @notice Claim right up to a percentage of term
     * @param manager AgreementManager contract address
     * @param tokenId Agreement ID Created in Agreement Manager
     * @param amount Amount to claim
     */
    function claim(
        IAgreementManager manager,
        uint256 tokenId,
        uint256 amount
    ) external;

    function claimable(IAgreementManager manager, uint256 tokenId) external view returns (uint256);
}

