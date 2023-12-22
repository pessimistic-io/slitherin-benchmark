// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.17;

import "./IMessageTransmitter.sol";

interface ITokenMessenger {
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken
    ) external returns (uint64 _nonce);

    function depositForBurnWithCaller(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller
    ) external returns (uint64 nonce);



    function localMessageTransmitter() external view returns (IMessageTransmitter);
}

