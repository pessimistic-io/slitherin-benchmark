// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IzkEVM {
    function send(
            address receiever,
            address token,
            uint256 amount,
            uint256 dstChainId,
            uint64 nonce,
            uint32 maxSlippage
        ) external;
}
