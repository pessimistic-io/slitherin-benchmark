//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./SmolFarmState.sol";

abstract contract SmolFarmContracts is Initializable, SmolFarmState {

    function __SmolFarmContracts_init() internal initializer {
        SmolFarmState.__SmolFarmState_init();
    }

    function setContracts(
        address _treasures,
        address _smolBrains,
        address _smolBodies,
        address _smolLand,
        address _randomizer)
    external onlyAdminOrOwner
    {
        treasures = ISmolTreasures(_treasures);
        smolBrains = IERC721(_smolBrains);
        smolBodies = IERC721(_smolBodies);
        smolLand = IERC721(_smolLand);
        randomizer = IRandomizer(_randomizer);
    }

    modifier contractsAreSet() {
        require(address(treasures) != address(0)
            && address(randomizer) != address(0)
            && address(smolBrains) != address(0)
            && address(smolBodies) != address(0)
            && address(smolLand) != address(0), "Contracts aren't set");

        _;
    }
}
