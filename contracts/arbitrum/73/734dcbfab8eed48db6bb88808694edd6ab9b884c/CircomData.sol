// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

struct CircomData {
    uint256 rootHashHinkal;

    uint256[] outCommitments;
    uint256 rootHashAccessToken;

    address relay;
    uint256 relayFee;

    int256 publicAmount;
//    address inErc20TokenAddress;
    address recipientAddress;

    uint256 externalActionId;
    uint256 externalActionMetadataHash;

    address inErc20TokenAddress;
    uint256 inAmount;

    address outErc20TokenAddress;
    uint256 outAmount;
}

