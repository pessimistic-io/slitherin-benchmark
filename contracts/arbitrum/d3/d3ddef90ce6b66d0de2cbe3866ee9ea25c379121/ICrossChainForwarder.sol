//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

interface ICrossChainForwarder {
    struct DstDetails {
        uint256 chainId;
        address receiver;
        bytes receiverCalldata;
        address fallbackAddress;
        bool useAssetFee;
        uint32 referralCode;
    }
}
