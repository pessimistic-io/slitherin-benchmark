//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ItemShopState.sol";

abstract contract ItemShopContracts is Initializable, ItemShopState {

    function __ItemShopContracts_init() internal initializer {
        ItemShopState.__ItemShopState_init();
    }

    function setContracts(
        address _bugzAddress,
        address _itemzAddress,
        address _badgezAddress)
    external onlyAdminOrOwner
    {
        bugz = IBugz(_bugzAddress);
        itemz = IItemz(_itemzAddress);
        badgez = IBadgez(_badgezAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "ItemShop: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(bugz) != address(0)
            && address(itemz) != address(0)
            && address(badgez) != address(0);
    }
}
