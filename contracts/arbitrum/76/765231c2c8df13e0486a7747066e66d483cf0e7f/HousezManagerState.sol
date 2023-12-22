//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC721HolderUpgradeable.sol";

import "./IHousezManager.sol";
import "./AdminableUpgradeable.sol";
import "./IToadHousez.sol";

abstract contract HousezManagerState is Initializable, IHousezManager, ERC721HolderUpgradeable, AdminableUpgradeable {

    event FloorInfoUpdated(uint16 _floorNum, uint16 _numHousezForFloor, uint16 _totalHousezStakable);

    event HouseStaked(address _owner, uint16 _houseId, uint16 _previousHouseId);
    event HouseUnstaked(address _owner, uint16 _houseId, uint16 _oldPreviousHouseId, uint16 _oldNextHouseId);

    IToadHousez public housez;

    uint16 public totalStakableHousez;

    mapping(uint16 => FloorInfo) public floorNumToInfo;

    mapping(address => UserInfo) internal userToInfo;
    mapping(uint16 => HouseInfo) public houseIdToInfo;

    function __HousezManagerState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();
    }
}

struct FloorInfo {
    // Slot 1 (16/248)
    // The number of housez needed to get the floor.
    // If 0, this floor cannot be built.
    uint16 numHousezForFloor;
    uint240 emptySpace;
}

struct UserInfo {
    // Slot 1 (48/256)
    // The id of the first staked house. Essentially points to the first item in the doubly linked list
    uint16 firstHouseId;
    // The id of the last staked house.
    uint16 lastHouseId;
    // The number of housez this user has staked.
    uint16 housezStaked;
    uint208 emptySpace;
}

struct HouseInfo {
    // Slot 1 (192/256)
    // The house id of the previous house in the ordered list. If 0, this is the first item.
    uint16 previousHouseId;
    // The house id of the next house in the ordered list. If 0, this is the last item.
    uint16 nextHouseId;
    // The owner of the house.
    address owner;
    uint64 emptySpace;
}
