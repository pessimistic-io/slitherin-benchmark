// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IHyphenBridge {
    function depositErc20(
        uint256 toChainId,
        address tokenAddress,
        address receiver,
        uint256 amount,
        string calldata tag
    ) external;
}

