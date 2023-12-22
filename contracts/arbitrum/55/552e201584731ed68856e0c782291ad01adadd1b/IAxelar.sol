// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAxelar {
    function sendToken(
        string memory destinationChain,
        string memory destinationAddress,
        string memory symbol,
        uint256 amount
    ) external;
}

