// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ICorruptionCryptsInternal.sol";

interface ICorruptionCryptsRewards {
    function onCharactersArrivedAtHarvester(
        address _harvesterAddress,
        CharacterInfo[] calldata _characters
    ) external;

    function onNewRoundBegin(
        address[] memory activeHarvesterAddresses
    ) external;
}

