//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./CorruptionCryptsRewardsState.sol";

abstract contract CorruptionCryptsRewardsContracts is Initializable, CorruptionCryptsRewardsState {

    function __CorruptionCryptsRewardsContracts_init() internal initializer {
        CorruptionCryptsRewardsState.__CorruptionCryptsRewardsState_init();
    }

    function setContracts(
        address _corruptionAddress,
        address _legionMetadataStoreAddress,
        address _corruptionCryptsAddress,
        address _consumableAddress)
    external onlyAdminOrOwner
    {
        corruption = ICorruption(_corruptionAddress);
        legionMetadataStore = ILegionMetadataStore(_legionMetadataStoreAddress);
        corruptionCrypts = ICorruptionCrypts(_corruptionCryptsAddress);
        consumable = IConsumable(_consumableAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "CorruptionCryptsRewards: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(corruption) != address(0)
            && address(legionMetadataStore) != address(0)
            && address(consumable) != address(0)
            && address(corruptionCrypts) != address(0);
    }
}
