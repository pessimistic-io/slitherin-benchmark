// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IHopBridge {
    function swapAndSend(
        uint256 chainId,
        address recipient,
        uint256 amount,
        uint256 bonderFee,
        uint256 amountOutMin,
        uint256 deadline,
        uint256 destinationAmountOutMin,
        uint256 destinationDeadline
    ) external;
}

