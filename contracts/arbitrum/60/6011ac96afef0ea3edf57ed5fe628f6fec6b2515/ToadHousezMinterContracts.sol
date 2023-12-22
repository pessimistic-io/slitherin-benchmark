//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ToadHousezMinterState.sol";

abstract contract ToadHousezMinterContracts is Initializable, ToadHousezMinterState {

    function __ToadHousezMinterContracts_init() internal initializer {
        ToadHousezMinterState.__ToadHousezMinterState_init();
    }

    function setContracts(
        address _randomizerAddress,
        address _itemzAddress,
        address _bugzAddress,
        address _toadzAddress,
        address _toadzMetadataAddress,
        address _toadHousezAddress,
        address _badgezAddress,
        address _worldAddress,
        address _wartlocksHallowAddress)
    external onlyAdminOrOwner
    {
        randomizer = IRandomizer(_randomizerAddress);
        itemz = IItemz(_itemzAddress);
        bugz = IBugz(_bugzAddress);
        toadz = IToadz(_toadzAddress);
        toadzMetadata = IToadzMetadata(_toadzMetadataAddress);
        toadHousez = IToadHousez(_toadHousezAddress);
        badgez = IBadgez(_badgezAddress);
        world = IWorld(_worldAddress);
        wartlocksHallow = IWartlocksHallow(_wartlocksHallowAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(randomizer) != address(0)
            && address(itemz) != address(0)
            && address(bugz) != address(0)
            && address(toadz) != address(0)
            && address(toadzMetadata) != address(0)
            && address(toadHousez) != address(0)
            && address(badgez) != address(0)
            && address(world) != address(0)
            && address(wartlocksHallow) != address(0);
    }
}
