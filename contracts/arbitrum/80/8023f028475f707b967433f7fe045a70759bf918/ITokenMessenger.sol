// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface ITokenMessenger {
    function depositForBurnWithCaller(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller
    ) external returns (uint64 nonce);
}

