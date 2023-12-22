// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface ISupraRouter {
    function generateRequest(
        string memory _functionSig,
        uint8 _rngCount,
        uint256 _numConfirmations
    ) external returns (uint256);
}

