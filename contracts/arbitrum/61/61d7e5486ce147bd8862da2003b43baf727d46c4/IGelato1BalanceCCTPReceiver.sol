// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IGelato1BalanceCCTPReceiver {
    function receiveAndDeposit(
        address _owner,
        bytes calldata _message,
        bytes calldata _attestation
    ) external;
}

