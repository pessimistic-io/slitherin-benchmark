// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ITokenMessenger {
    function depositForBurn(
        uint256 _amount,
        uint32 _destinationDomain,
        bytes32 _mintRecipient,
        address _burnToken
    ) external returns (uint64);

    function depositForBurnWithCaller(
        uint256 _amount,
        uint32 _destinationDomain,
        bytes32 _mintRecipient,
        address _burnToken,
        bytes32 _destinationCaller
    ) external returns (uint64);

    function replaceDepositForBurn(
        bytes memory originalMessage,
        bytes calldata originalAttestation,
        bytes32 _destCaller,
        bytes32 _mintRecipient
    ) external;
}

