//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./TLDMinterState.sol";

abstract contract TLDMinterContracts is Initializable, TLDMinterState {
    function __TLDMinterContracts_init() internal initializer {
        TLDMinterState.__TLDMinterState_init();
    }

    function setContracts(address _tldAddress) external onlyAdminOrOwner {
        tld = ITLD(_tldAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "TLDMinter: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns (bool) {
        return address(tld) != address(0);
    }
}

