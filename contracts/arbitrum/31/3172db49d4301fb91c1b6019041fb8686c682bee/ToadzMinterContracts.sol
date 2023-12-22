//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ToadzMinterState.sol";

abstract contract ToadzMinterContracts is Initializable, ToadzMinterState {

    function __ToadzMinterContracts_init() internal initializer {
        ToadzMinterState.__ToadzMinterState_init();
    }

    function setContracts(
        address _toadzAddress,
        address _randomizerAddress,
        address _badgezAddress,
        address _itemzAddress)
    external onlyAdminOrOwner
    {
        toadz = IToadz(_toadzAddress);
        randomizer = IRandomizer(_randomizerAddress);
        badgez = IBadgez(_badgezAddress);
        itemz = IItemz(_itemzAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "ToadzMinter: Contracts aren't set");

        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(toadz) != address(0)
            && address(randomizer) != address(0)
            && address(badgez) != address(0)
            && address(itemz) != address(0);
    }
}
