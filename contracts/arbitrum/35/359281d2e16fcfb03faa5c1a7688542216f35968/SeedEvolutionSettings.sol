//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./SeedEvolutionContracts.sol";

abstract contract SeedEvolutionSettings is Initializable, SeedEvolutionContracts {

    function __SeedEvolutionSettings_init() internal initializer {
        SeedEvolutionContracts.__SeedEvolutionContracts_init();
    }

    function setTimelineSettings(
        uint256 _timeUntilOffensiveSkill,
        uint256 _timeUntilFirstSecondarySkill,
        uint256 _timeUntilSecondSecondarySkill,
        uint256 _timeUntilDeath)
    external
    onlyAdminOrOwner
    {
        timeUntilOffensiveSkill = _timeUntilOffensiveSkill;
        timeUntilFirstSecondarySkill = _timeUntilFirstSecondarySkill;
        timeUntilSecondSecondarySkill = _timeUntilSecondSecondarySkill;
        timeUntilDeath = _timeUntilDeath;
    }

    function setBaseTokenUri(string calldata _baseTokenUri) external onlyAdminOrOwner {
        baseTokenUri = _baseTokenUri;
    }

}
