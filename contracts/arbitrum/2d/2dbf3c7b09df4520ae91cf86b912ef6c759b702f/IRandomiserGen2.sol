// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.18;

interface IRandomiserGen2 {
    function getRandomNumber(
        address callbackContract,
        uint32 callbackGasLimit,
        uint16 minConfirmations
    ) external payable returns (uint256 requestId);
}

