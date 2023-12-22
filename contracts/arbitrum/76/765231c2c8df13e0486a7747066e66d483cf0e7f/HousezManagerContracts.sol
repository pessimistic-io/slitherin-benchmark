//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./HousezManagerState.sol";

abstract contract HousezManagerContracts is Initializable, HousezManagerState {

    function __HousezManagerContracts_init() internal initializer {
        HousezManagerState.__HousezManagerState_init();
    }

    function setContracts(
        address _toadHousezAddress)
    external onlyAdminOrOwner
    {
        housez = IToadHousez(_toadHousezAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(housez) != address(0);
    }
}
