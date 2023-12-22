// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract Errors {
    error NotGuardian();
    error GamePaused();
    error GameAlreadyUnPaused();
    error UnsupportedCreditType();
    error InvalidArrayLength();
    error IncorrectTreasuresAmount();
    error InvalidAmount();
    error UnsupportedPaymentType();
    error InvalidAddress();
    error InsufficientMagicForLpAmount();
    error InsufficientGFlyForLpAmount();
    error IdenticalAddresses();
    error NotBattleflyBot();

    error NotSoulbound();
    error IncorrectSigner(address signer);
    error NotOwnerOfBattlefly(address account, uint256 tokenId, uint256 tokenType);
    error InvalidTokenType(uint256 tokenId, uint256 tokenType);

    error InvalidEpoch(uint256 epoch, uint256 emissionsEpoch);
    error InvalidProof(bytes32[] merkleProof, bytes32 merkleRoot, bytes32 node);
    error NotEmissionDepositor();

    error NotBackendExecutor();

    error InvalidCurrency();
    error InvalidEthAmount();
    error EthTransferFailed();

    error NotGameV2();
    error InsufficientAmount();
    error SequencerDown();
    error GracePeriodNotOver();
}

