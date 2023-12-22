//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./RecruitLevelState.sol";

abstract contract RecruitLevelContracts is Initializable, RecruitLevelState {

    function __RecruitLevelContracts_init() internal initializer {
        RecruitLevelState.__RecruitLevelState_init();
    }

    function setContracts(
        address _legionMetadataStoreAddress,
        address _consumableAddress,
        address _legionAddress)
    external onlyAdminOrOwner
    {
        legionMetadataStore = ILegionMetadataStore(_legionMetadataStoreAddress);
        consumable = IConsumable(_consumableAddress);
        legion = ILegion(_legionAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "RecruitLevel: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(legionMetadataStore) != address(0)
            && address(consumable) != address(0)
            && address(legion) != address(0);
    }
}
