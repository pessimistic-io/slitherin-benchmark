// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICorruptionCryptsRewards {
    function onLegionsArrivedAtHarvester(
        address _harvesterAddress,
        uint32[] calldata _legionIds
    ) external;

    function onNewRoundBegin(
        address[] memory activeHarvesterAddresses
    ) external;
}
