// SPDX-License-Identifier: SHIFT-1.0
pragma solidity ^0.8.20;

interface IRemoteDefiiPrincipal {
    function mintShares(
        address vault,
        uint256 positionId,
        uint256 shares
    ) external;
}

