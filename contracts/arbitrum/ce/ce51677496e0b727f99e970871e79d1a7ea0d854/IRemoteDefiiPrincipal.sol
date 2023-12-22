// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IRemoteDefiiPrincipal {
    function mintShares(
        address vault,
        uint256 positionId,
        uint256 shares
    ) external;
}

