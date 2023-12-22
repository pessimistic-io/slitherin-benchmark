//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./SmolRacingState.sol";

abstract contract SmolRacingAdmin is Initializable, SmolRacingState {

    // -------------------------------------------------------------
    //                         Initializer
    // -------------------------------------------------------------

    function __SmolRacingAdmin_init() internal initializer {
        SmolRacingState.__SmolRacingState_init();
    }

    // -------------------------------------------------------------
    //                      External functions
    // -------------------------------------------------------------

    function setContracts(
        address _treasures,
        address _smolBrains,
        address _smolBodies,
        address _smolCars,
        address _swolercycles,
        address _racingTrophies,
        address _randomizer)
    external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE)
    {
        treasures = ISmolTreasures(_treasures);
        smolBrains = IERC721(_smolBrains);
        smolBodies = IERC721(_smolBodies);
        smolCars = IERC721(_smolCars);
        swolercycles = IERC721(_swolercycles);
        racingTrophies = ISmolRacingTrophies(_racingTrophies);
        randomizer = IRandomizer(_randomizer);
    }

    function setRewards(
        uint256[] calldata _rewardIds,
        uint32[] calldata _rewardOdds)
    external
    requiresEitherRole(ADMIN_ROLE, OWNER_ROLE)
    {
        require(_rewardIds.length == _rewardOdds.length, "Bad lengths");

        delete rewardOptions;

        uint32 _totalOdds;
        for(uint256 i = 0; i < _rewardIds.length; i++) {
            _totalOdds += _rewardOdds[i];

            rewardOptions.push(_rewardIds[i]);
            rewardIdToOdds[_rewardIds[i]] = _rewardOdds[i];
        }

        require(_totalOdds == ODDS_DENOMINATOR, "Bad total odds");
    }

    function setTimeForReward(uint256 _rewardTime) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        timeForReward = _rewardTime;
    }

    function setEndTimeForEmissions(uint256 _endTime) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        endEmissionTime = _endTime;
    }

    // -------------------------------------------------------------
    //                           Modifiers
    // -------------------------------------------------------------

    modifier contractsAreSet() {
        require(areContractsSet(), "Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(treasures) != address(0)
            && address(randomizer) != address(0)
            && address(smolBrains) != address(0)
            && address(smolBodies) != address(0)
            && address(smolCars) != address(0)
            && address(swolercycles) != address(0)
            && address(racingTrophies) != address(0);
    }
}
