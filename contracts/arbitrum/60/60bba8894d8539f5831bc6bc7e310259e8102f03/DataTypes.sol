// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

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
        uint64 platformFee;
        uint64 withdrawFee;
        address treasury;
    }

    struct withdrawRequest {
        address receiver;
        uint256 amount;
    }
}

