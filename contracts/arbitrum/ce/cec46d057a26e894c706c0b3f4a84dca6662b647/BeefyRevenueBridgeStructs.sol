// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract BeefyRevenueBridgeStructs {
    struct BridgeParams {
        address bridge;
        bytes params;
    }

    struct SwapParams {
        address router;
        bytes params;
    }

    struct DestinationAddress {
        address destination;
        bytes destinationBytes;
        string destinationString;
    }

    struct Stargate {
        uint16 dstChainId;
        uint256 gasLimit;
        uint256 srcPoolId; 
        uint256 dstPoolId;
    }
    
    struct Axelar {
        string destinationChain;
        string symbol;
    }

    struct Synapse {
        uint256 chainId;
        uint8 tokenIndexFrom;
        uint8 tokenIndexTo;
    }
}
