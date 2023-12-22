// SPDX-License-Identifier: SHIFT-1.0
pragma solidity ^0.8.20;

interface IRemoteDefiiAgent {
    function increaseShareBalance(
        address vault,
        uint256 positionId,
        address owner,
        uint256 shares
    ) external;
}

