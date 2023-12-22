// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

library RangoHopModels {
    enum ActionType { SWAP_AND_SEND, SEND_TO_L2 }

    struct HopRequest {
        ActionType actionType;
        address bridgeAddress;
        uint256 chainId;
        address recipient;
        uint256 bonderFee;
        uint256 amountOutMin;
        uint256 deadline;
        uint256 destinationAmountOutMin;
        uint256 destinationDeadline;
        address relayer;
        uint256 relayerFee;
    }

}
