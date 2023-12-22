// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface IFirebirdRouterArbitrum {
    struct SwapDescription {
        address srcToken;
        address dstToken;
        address srcReceiver;
        address dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
        bytes permit;
    }

    function swap(
        address caller,
        SwapDescription calldata desc,
        bytes calldata data
    ) external payable returns (uint256 returnAmount); // 0x7c025200
}

