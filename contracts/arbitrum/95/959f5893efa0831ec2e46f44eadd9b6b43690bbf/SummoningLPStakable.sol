//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";

import "./SummoningTimeKeeper.sol";
import "./ILegionMetadataStore.sol";

abstract contract SummoningLPStakable is Initializable, SummoningTimeKeeper {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function __SummoningLPStakable_init() internal initializer {
        SummoningTimeKeeper.__SummoningTimeKeeper_init();
    }

    function _lpNeeded(LegionGeneration _generation, uint32 _summoningCountCur) internal view returns(uint256) {
        SummoningStep[] memory _steps = generationToLPRequiredSteps[_generation];

        for(uint256 i = 0; i < _steps.length; i++) {
            SummoningStep memory _step = _steps[i];

            if(_summoningCountCur > _step.maxSummons) {
                continue;
            } else {
                return _step.value;
            }
        }

        // Shouldn't happen since the steps should go up to max value of uint32. If it does, we should not let them continue.
        revert("Bad LP step values");
    }
}
