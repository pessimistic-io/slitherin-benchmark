//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ConsumableClaimerState.sol";

abstract contract ConsumableClaimerContracts is Initializable, ConsumableClaimerState {

    function __ConsumableClaimerContracts_init() internal initializer {
        ConsumableClaimerState.__ConsumableClaimerState_init();
    }

    function setContracts(
        address _consumableAddress)
    external onlyAdminOrOwner
    {
        consumable = IConsumable(_consumableAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "ConsumableClaimer: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(consumable) != address(0);
    }
}
