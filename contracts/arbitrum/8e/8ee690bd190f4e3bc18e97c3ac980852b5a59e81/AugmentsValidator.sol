// SPDX-License-Identifier: AGPL-3.0


pragma solidity ^0.8.0;

import "./verification_Context.sol";
import "./ICharacter.sol";
import "./ICore.sol";
import "./verification_Auth.sol";

// Note: try to minimize the contract depth that mutative actions have to take
contract AugmentsValidator is Context, Auth {
  ICore public core;
  ICharacter public character;
  mapping(uint256 => bool) public augmentExists;
  uint16 public slotCount;
  mapping(uint256 => string) public cid;
  mapping(string => uint256) public id;

  // Change to initialize call
  constructor(
    ICharacter _character,
    ICore _core,
    Authority auth
  ) Auth(msg.sender, auth) {
    core = _core;
    character = _character;
  }

  function equipSkeleton(uint256 id, uint16 slotID) external {
    require(uint8(id) == uint8(slotID), "This doesn't fit in this slot");
    character.equipSkeleton(slotID, id, msg.sender);
  }

  function unequipSkeleton(uint16 slotID) external {
    character.unequipSkeleton(slotID, msg.sender);
  }

  function addAugment(
    uint32 series,
    uint16 slot,
    uint8 form,
    uint8 rarity
  ) external requiresAuth {
    augmentExists[convertToAugmentUUID(series, slot, form, rarity)] = true;
  }

  function removeAugment(
    uint32 series,
    uint16 slot,
    uint8 form,
    uint8 rarity
  ) external requiresAuth {
    augmentExists[convertToAugmentUUID(series, slot, form, rarity)] = false;
  }

  // Unclear if slot should be at the top, or the bottom of this config?
  function convertToAugmentUUID(
    uint32 series,
    uint16 slot,
    uint8 form,
    uint8 rarity
  ) public pure returns (uint256 id) {
    //solhint-disable-next-line
    assembly {
      // Bitshift and Pack series, rarity, and slot into ID -- [series][rarity][slot]
      id := add(
        add(add(slot, mul(rarity, 0x10000)), mul(form, 0x1000000)),
        mul(series, 0x100000000)
      )
    }
  }

  function setCID(uint256 _id, string calldata _cid) external {
    cid[_id] = _cid;
    id[_cid] = _id;
  }

  function uri(uint256 id) external view returns (string memory) {
    return core.uri(id);
  }
}

