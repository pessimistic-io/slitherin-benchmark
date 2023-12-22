//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./LegionState.sol";

abstract contract LegionContracts is Initializable, LegionState {

    function __LegionContracts_init() internal initializer {
        LegionState.__LegionState_init();
    }

    function setContracts(
        address _legionMetadataStoreAddress)
    external onlyAdminOrOwner
    {
        legionMetadataStore = ILegionMetadataStore(_legionMetadataStoreAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "Legion: Contracts aren't set");

        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(legionMetadataStore) != address(0);
    }
}
