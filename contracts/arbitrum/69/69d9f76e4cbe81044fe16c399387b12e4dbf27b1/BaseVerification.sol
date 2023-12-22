// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

abstract contract BaseVerifier {
    struct SocketRequest {
        uint256 amount;
        address recipient;
        uint256 toChainId;
        address token;
        bytes4 signature;
    }
}
