//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./CorruptionRemovalState.sol";

abstract contract CorruptionRemovalContracts is Initializable, CorruptionRemovalState {

    function __CorruptionRemovalContracts_init() internal initializer {
        CorruptionRemovalState.__CorruptionRemovalState_init();
    }

    function setContracts(
        address _randomizerAddress,
        address _corruptionAddress,
        address _consumableAddress,
        address _treasuryAddress,
        address _balancerCrystalAddress)
    external onlyAdminOrOwner
    {
        randomizer = IRandomizer(_randomizerAddress);
        corruption = ICorruption(_corruptionAddress);
        consumable = IConsumable(_consumableAddress);
        treasuryAddress = _treasuryAddress;
        balancerCrystal = IBalancerCrystal(_balancerCrystalAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "CorruptionRemoval: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(randomizer) != address(0)
            && address(corruption) != address(0)
            && address(consumable) != address(0)
            && treasuryAddress != address(0)
            && address(balancerCrystal) != address(0);
    }
}
