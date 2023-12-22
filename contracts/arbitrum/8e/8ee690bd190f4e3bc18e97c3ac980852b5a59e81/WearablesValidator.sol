// SPDX-License-Identifier: AGPL-3.0


pragma solidity ^0.8.0;

import "./verification_Context.sol";
import "./ICharacter.sol";
import "./IWearables.sol";
import "./ICore1155.sol";
import "./verification_Auth.sol";
import "./LegacyPills.sol";

// Note: try to minimize the contract depth that mutative actions have to take
contract WearablesValidator is Context, Auth, IWearables {
  ICore1155 public core;
  ICharacter public character;
  mapping(uint256 => bool) public wearableExists;
  uint8 public slotCount;
  mapping(uint256 => string) public cid;
  mapping(string => uint32) public id;
  mapping(uint256 => string[]) public legacyPill;
  mapping(string => Wearable) public wearables;
  mapping(uint256 => bool) public isEgodeth;

  struct Wearable {
    uint16 slot;
    uint8 form;
    uint8 rarity;
  }

  // Change to initialize call
  constructor(
    ICharacter _character,
    ICore1155 _core,
    Authority auth
  ) Auth(msg.sender, auth) {
    core = _core;
    character = _character;
  }

  function equipSkeleton(uint256 id, uint16 slotID) external {
    require(uint16(id) == slotID, "This doesn't fit in this slot");
    character.equipSkeleton(slotID, id, msg.sender);
  }

  function unequipSkeleton(uint8 slotID) external {
    character.unequipSkeleton(slotID, msg.sender);
  }

  function addWearable(
    uint16 slot,
    uint8 form,
    uint8 rarity,
    string calldata _cid
  ) external requiresAuth {
    wearableExists[convertToWearableUUID(slot, form, rarity)] = true;
    wearables[_cid] =  Wearable(slot, form, rarity);
  }

  function getSlot(string calldata _cid) external view returns (uint16 slot) {
    slot = wearables[_cid].slot;
  }

  function removeWearable(
    uint16 slot,
    uint8 form,
    uint8 rarity
  ) external requiresAuth {
    wearableExists[convertToWearableUUID(slot, form, rarity)] = false;
  }

  function setIdtoStringPill(uint256 pillId, uint256 form, string calldata _cid) external {
    uint256 subType = LegacyPills.getSubTypeFromId(pillId);
    uint256 pillType = LegacyPills.getTypeFromId(pillId);
    uint256 egoDethShift = isEgodeth[subType] ? 1 : 0;
    if(pillType == 1 && egoDethShift == 1) {
      pillType = LegacyPills.getRootIdFromId(pillId);
    }
    legacyPill[pillType + (256 * (form+1)) + (1024 * (egoDethShift+1))].push(_cid);
  }

  function removeIdfromStringPill(uint256 pillId, uint256 form, uint256 index) external {
    uint256 subType = LegacyPills.getSubTypeFromId(pillId);
    uint256 pillType = LegacyPills.getTypeFromId(pillId);
    uint256 egoDethShift = isEgodeth[subType] ? 1 : 0;
    if(pillType == 1 && egoDethShift == 1) {
      pillType = LegacyPills.getRootIdFromId(pillId);
    }
    string[] storage arr = legacyPill[pillType + (256 * (form+1)) + (1024 * (egoDethShift+1))];
    arr[index] = arr[arr.length - 1];
    arr.pop();
  }

  function getEquipmentFromPill(uint256 pillId, uint256 form) public view returns (string[] memory) {
    uint256 subType = LegacyPills.getSubTypeFromId(pillId);
    uint256 pillType = LegacyPills.getTypeFromId(pillId);
    uint256 egoDethShift = isEgodeth[subType] ? 1 : 0;
    if(pillType == 1 && egoDethShift == 1) {
      pillType = LegacyPills.getRootIdFromId(pillId);
    }
    return legacyPill[pillType + (256 * (form+1)) + (1024 * (egoDethShift+1))];
  }

  function setEgodeth(uint256 subType, bool isEgo) external {
    isEgodeth[subType] = isEgo;
  }

  // Unclear if slot should be at the top, or the bottom of this config?
  function convertToWearableUUID(
    uint16 slot,
    uint8 form,
    uint8 rarity
  ) public pure returns (uint256 id) {
    //solhint-disable-next-line
    assembly {
      // Bitshift and Pack series, rarity, and slot into ID -- [series][rarity][slot]
      id := add(add(slot, mul(rarity, 0x100)), mul(form, 0x10000))
    }
  }

  function setCID(uint32 _id, string calldata _cid) external {
    cid[_id] = _cid;
    id[_cid] = _id;
  }

  function uri(uint32 _id) external view returns (string memory) {
    return core.uri(_id);
  }

  function mintEquipment(address target, uint256 item) external {
    uint256[] memory idReturn = new uint256[](1);
    uint256[] memory quantityReturn = new uint256[](1);
    idReturn[0] = item;
    quantityReturn[0] = 1;
    core.modularMintCallback(target, idReturn, quantityReturn, "");
  } 

}

