// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

library DataTypes {
    struct PositionData {
        address adaptor;
        bytes adaptorData;
        bytes configurationData;
    }

    struct AdaptorCall {
        address adaptor;
        bytes callData;
    }

    struct feeData {
        uint64 performanceFee;
        uint64 withdrawFee;
        address treasury;
    }

    struct withdrawRequest {
        address receiver;
        uint256 shares;
        uint256 id;
    }

    struct ProtocolSelectors {
        bytes4 deposit;
        bytes4 withdraw;
    }
}

