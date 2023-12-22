//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./WanderingMerchantState.sol";

abstract contract WanderingMerchantContracts is Initializable, WanderingMerchantState {

    function __WanderingMerchantContracts_init() internal initializer {
        WanderingMerchantState.__WanderingMerchantState_init();
    }

    function setContracts(
        address _consumableAddress,
        address _legionAddress,
        address _legionMetadataStoreAddress)
    external onlyAdminOrOwner
    {
        consumable = IConsumable(_consumableAddress);
        legion = ILegion(_legionAddress);
        legionMetadataStore = ILegionMetadataStore(_legionMetadataStoreAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "WanderingMerchant: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(consumable) != address(0)
            && address(legion) != address(0)
            && address(legionMetadataStore) != address(0);
    }
}
