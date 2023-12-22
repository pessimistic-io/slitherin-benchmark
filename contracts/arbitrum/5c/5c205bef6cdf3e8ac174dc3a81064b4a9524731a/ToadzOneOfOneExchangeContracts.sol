//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ToadzOneOfOneExchangeState.sol";

abstract contract ToadzOneOfOneExchangeContracts is Initializable, ToadzOneOfOneExchangeState {

    function __ToadzOneOfOneExchangeContracts_init() internal initializer {
        ToadzOneOfOneExchangeState.__ToadzOneOfOneExchangeState_init();
    }

    function setContracts(
        address _toadzAddress,
        address _toadzMetadataAddress)
    external onlyAdminOrOwner
    {
        toadz = IToadz(_toadzAddress);
        toadzMetadata = IToadzMetadata(_toadzMetadataAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "ToadzOneOfOneExchange: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(toadz) != address(0)
            && address(toadzMetadata) != address(0);
    }
}
