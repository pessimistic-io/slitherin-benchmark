//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./AdvancedQuestingFixState.sol";

abstract contract AdvancedQuestingFixContracts is Initializable, AdvancedQuestingFixState {

    function __AdvancedQuestingFixContracts_init() internal initializer {
        AdvancedQuestingFixState.__AdvancedQuestingFixState_init();
    }

    function setContracts(
        address _advancedQuestingAddress)
    external onlyAdminOrOwner
    {
        advancedQuesting = IAdvancedQuesting(_advancedQuestingAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "AdvancedQuestingFix: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(advancedQuesting) != address(0);
    }
}
