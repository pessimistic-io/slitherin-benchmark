// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct ClaimInfo {
    address claimer;
    address badgeAddress;
    uint256 badgeId;
    bytes32 nonce;
    uint256 priceInUSD;
    address paymentToken;
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
    // Raised when there is a payment requirement for minting that was not met.
    error InsufficientValue();
    // Raised when the payment token differs in batch claims
    error InvalidPaymentToken();

    function claim(ClaimInfo calldata _claimInfo, bytes memory _authoritySignature) external payable;
    function claimBatch(ClaimInfo[] calldata _claimInfos, bytes[] memory _authoritySignatures) external payable;
}

