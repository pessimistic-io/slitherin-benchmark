//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./TLDState.sol";

abstract contract TLDContracts is Initializable, TLDState {
    function __TLDContracts_init() internal initializer {
        TLDState.__TLDState_init();
    }

    function setContracts(address _tldMetadata) external onlyAdminOrOwner {
        tldMetadata = ITLDMetadata(_tldMetadata);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "TLD: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns (bool) {
        return address(tldMetadata) != address(0);
    }
}

