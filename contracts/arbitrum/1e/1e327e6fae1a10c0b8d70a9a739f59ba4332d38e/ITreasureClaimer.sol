// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct ClaimInfo {
    address claimer;
    address badgeAddress;
    uint256 badgeId;
    bytes32 nonce;
}

interface ITreasureClaimer {
    // Emitted when a claim is successful.
    event BadgeClaimed(address indexed claimer, address indexed badgeAddress, uint256 indexed badgeId, bytes32 nonce);
    // Emitted when a claim has been undone by the admin (under exceptional circumstances).
    event BadgeUnclaimed(address indexed claimer, address indexed badgeAddress, uint256 indexed badgeId, bytes32 nonce);

    // Raised when these parameters have already been used to claim a badge.
    error BadgeAlreadyClaimed(address claimer, address badgeAddress, uint256 badgeId, bytes32 nonce);
    // Raised when the badge is not enabled.
    error InvalidBadge(address badgeAddress, uint256 badgeId);
    // Raised when the signature for a claim is invalid.
    error InvalidSignature(address signer);
    // Raised when the message sender is not the claimer for a claim attempt.
    error NotRecipient();

    function claim(ClaimInfo calldata _claimInfo, bytes memory _authoritySignature) external;
}

