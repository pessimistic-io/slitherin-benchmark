//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./BeaconQuestingState.sol";

abstract contract BeaconQuestingContracts is Initializable, BeaconQuestingState {

    function __BeaconQuestingContracts_init() internal initializer {
        BeaconQuestingState.__BeaconQuestingState_init();
    }

    function setContracts(
        address _randomizerAddress,
        address _masterOfInflationAddress,
        address _beaconAddress)
    external onlyAdminOrOwner
    {
        randomizer = IRandomizer(_randomizerAddress);
        masterOfInflation = IMasterOfInflation(_masterOfInflationAddress);
        beacon = IBeacon(_beaconAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "BeaconQuesting: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(randomizer) != address(0)
            && address(masterOfInflation) != address(0)
            && address(beacon) != address(0);
    }
}
