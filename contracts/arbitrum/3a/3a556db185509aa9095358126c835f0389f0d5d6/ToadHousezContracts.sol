//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ToadHousezState.sol";

abstract contract ToadHousezContracts is Initializable, ToadHousezState {

    function __ToadHousezContracts_init() internal initializer {
        ToadHousezState.__ToadHousezState_init();
    }

    function setContracts(
        address _toadHousezMetadataAddress)
    external
    onlyAdminOrOwner
    {
        toadHousezMetadata = IToadHousezMetadata(_toadHousezMetadataAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "Toadz: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(toadHousezMetadata) != address(0);
    }
}
