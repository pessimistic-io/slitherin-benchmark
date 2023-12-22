// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IVariableRateTransfers {
    struct Signature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct Transfer {
        string id;
        string invoiceId;
        address from;
        address to;
        address token;
        uint256 amount;
        bool usd;
    }

    struct TransferParams {
        Transfer data;
        Signature signature;
    }

    struct OperatorInitParams {
        address inboundTreasury;
        address outboundTreasury;
        address signer;
    }

    enum SecurityLevel {
        DIRECT,
        PLATFORM
    }

    enum OperatorAddress {
        INBOUND_TREASURY,
        OUTBOUND_TREASURY,
        SIGNER
    }
}

