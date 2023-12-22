//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ToadzState.sol";

abstract contract ToadzContracts is Initializable, ToadzState {

    function __ToadzContracts_init() internal initializer {
        ToadzState.__ToadzState_init();
    }

    function setContracts(
        address _toadzMetadataAddress)
    external
    onlyAdminOrOwner
    {
        toadzMetadata = IToadzMetadata(_toadzMetadataAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "Toadz: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(toadzMetadata) != address(0);
    }
}
