//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Initializable.sol";
import "./DonkeBoardState.sol";

abstract contract DonkeBoardContracts is Initializable, DonkeBoardState {
    function __DonkeBoardContracts_init() internal initializer {
        DonkeBoardState.__DonkeBoardState_init();
    }

    function setContracts(
        address _donkeBoardMetadata
    ) external onlyAdminOrOwner {
        donkeBoardMetadata = IDonkeBoardMetadata(_donkeBoardMetadata);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "DonkeBoardContracts: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns (bool) {
        return address(donkeBoardMetadata) != address(0);
    }
}

