// SPDX-License-Identifier: AGPL-3.0


pragma solidity ^0.8.0;
import "./LegacyPills.sol";
//Interface

interface IToken {
  function balanceOf(address account, uint256 id)
    external
    view
    returns (uint256);
}

contract SelectableOptions {
  string private constant _HASHMONK_FORM = "Hashmonk";
  string private constant _PEPEL_FORM = "Pepel";
  string private constant _MOUTH = "Mouth";
  string private constant _EYES = "Eyes";
  string private constant _TYPE = "Type";
  string private constant _MARKINGS = "Markings";
  string private constant _CROWN = "Crown";
  string private constant _HEAD = "Head";
  string private constant _TORSO = "Torso";
  string private constant _LARM = "LeftArm";
  string private constant _RARM = "RightArm";
  string private constant _LLEG = "LeftLeg";
  string private constant _RLEG = "RightLeg";

  enum Requirement {
    None,
    HasEth,
    HasLegacyPill,
    HasCollabPill,
    HasTrait,
    HasNotTrait
  }
  // Extremely unwieldly struct; do better?
  struct Option {
    Requirement req; // 1 = HAS ETH, 2 = HAS PILL, 3 = Has TRAIT, 4 = HAS NOT TRAIT
    uint256 form;
    string name;
    string slot;
    string option;
  }

  string[] private _forms = [_HASHMONK_FORM, _PEPEL_FORM];

  // For each option what exactly are we checking?
  mapping(uint256 => uint256) private _idToEthCost;
  mapping(uint256 => uint256) private _idToLegacyPillReq;
  mapping(uint256 => uint256) public legacyPillToId;
  mapping(uint256 => uint256) private _idToCollabPillReq;
  mapping(uint256 => uint256) private collabPillToId;

  mapping(uint256 => string) private _idToTraitReq;

  // Mapping between the string rep of the selected character option and the fully qualified option requirements
  mapping(uint256 => Option) private _options;

  mapping(string => uint256) private _optionToId;
  uint256 private _optionCount;
  uint256 private _optionIndex = 65;

  address private _legacyPills;
  address private _collabPills;

  constructor(address legacyPills_, address collabPills_) {
    _legacyPills = legacyPills_;
    _collabPills = collabPills_;
  }


  function validateFaction(string calldata _faction, uint256 legacyPillId, address target) public view returns (bool) {
    uint256 id = _optionToId[_faction];
    require(id != 0, "Invalid faction");
    if(_options[id].req == Requirement.HasLegacyPill){
          require(
            IToken(_legacyPills).balanceOf(target, legacyPillId) > 0 &&
              _idToLegacyPillReq[id] == LegacyPills.getTypeFromId(legacyPillId),
            "You do not have the required Legacy pill"
          );
    }
    return true;
  }

  // TODO: Slim this THE FUCK down; use split functions for each index this is trash
  function validateOption(
    string[] calldata options,
    uint256 index,
    uint256 ethValue,
    uint256[] calldata legacyPillId,
    address target
  ) external view returns (uint256) {
    uint256 id = _optionToId[options[index]];
    Option memory op = _options[id];
    Requirement req = op.req;
    string memory form = _forms[op.form]; // Hashmonk or Pepel
    require(_compareCall(options[0], form), "Forms don't match");
    // TODO: Is there a smarter/more efficient/more extensible version of this?
    // Can probably convert this to an ASS switch
    if (_compareMem(form, _PEPEL_FORM)) {
      if (index == 5) {
        require(_compareMem(op.slot, _MOUTH), "invalid mouth");
      } else if (index == 6) {
        require(_compareMem(op.slot, _EYES), "invalid eyes");
      } else if (index == 7) {
        require(_compareMem(op.slot, _TYPE), "invalid type");
      } else if (index == 8) {
        require(_compareMem(op.slot, _MARKINGS), "invalid markings");
      } else {
        revert("invalid index");
      }
    } else if (_compareMem(form, _HASHMONK_FORM)) {
      if (index == 5) {
        require(_compareMem(op.slot, _HEAD), "invalid head");
      } else if (index == 6) {
        require(_compareMem(op.slot, _TORSO), "invalid torso");
      } else if (index == 7) {
        require(_compareMem(op.slot, _LARM), "invalid left arm");
      } else if (index == 8) {
        require(_compareMem(op.slot, _RARM), "invalid right arm");
      } else if (index == 9) {
        require(_compareMem(op.slot, _LLEG), "invalid left leg");
      } else if (index == 10) {
        require(_compareMem(op.slot, _RLEG), "invalid right leg");
      } else if (index == 11) {
        require(_compareMem(op.slot, _TYPE), "invalid color");
      } else if (index == 12) {
        require(_compareMem(op.slot, _CROWN), "invalid crown");
      } else {
        revert("invalid index");
      }
    }

    // HAS ETH
    if (req == Requirement.HasEth) {
      _checkHasEth(id, ethValue);
    }
    // HAS LEGACY PILL
    else if (req == Requirement.HasLegacyPill) {
      _checkHasLegacyPill(id, legacyPillId, target);
    }
    // HAS COLLAB PILL
    else if (req == Requirement.HasCollabPill) {
      _checkHasCollabPill(id, target);
    }
    // HAS TRAIT
    else if (req == Requirement.HasTrait) {
      _checkHasTrait(id, options);
    }
    // HAS NOT TRAIT
    else if (req == Requirement.HasNotTrait) {
      _checkHasNotTrait(id, options);
    }
    return id;
  }

  function getOption(string calldata option)
    external
    view
    returns (Option memory op)
  {
    op = _options[_optionToId[option]];
  }

  function getOptionId(string calldata option) external view returns (uint256) {
    return _optionToId[option];
  }

  // TODO: Put this somewhere better plx; memory vs calldata mismatch
  function _compareCall(string calldata a, string memory b)
    internal
    pure
    returns (bool)
  {
    if (bytes(a).length != bytes(b).length) {
      return false;
    } else {
      return keccak256(bytes(a)) == keccak256(bytes(b));
    }
  }

  // TODO: Issue with overload? Potentially rename; has caused issues before
  function _compareMem(string memory a, string memory b)
    internal
    pure
    returns (bool)
  {
    if (bytes(a).length != bytes(b).length) {
      return false;
    } else {
      return keccak256(bytes(a)) == keccak256(bytes(b));
    }
  }

  // TODO: Issue with overload? Potentially rename; has caused issues before
  function _compareMem2Call(string memory a, string calldata b)
    internal
    pure
    returns (bool)
  {
    if (bytes(a).length != bytes(b).length) {
      return false;
    } else {
      return keccak256(bytes(a)) == keccak256(bytes(b));
    }
  }

  function addOptionWithId(
    string calldata option,
    uint256 id,
    string calldata name,
    string calldata slot,
    uint256 form
  ) public {
    _addOption(option, id, name, slot, form);
  }

  function getOptionStringFromId(uint256 id) public view returns (string memory op) {
    op = _options[id].option;
  }

  function getSlotFromId(uint256 id) external view returns (string memory op) {
    op = _options[id].slot;
  }

  function getFormFromId(uint256 id) external view returns (uint256 op) {
    op = _options[id].form;
  }

  function addOption(
    string calldata option,
    string calldata name,
    string calldata slot,
    uint256 form
  ) public {
      unchecked {
      _optionIndex = _optionIndex + 1;
    }
    _addOption(option, _optionIndex, name, slot, form);

  }

  function _addOption(
    string calldata optionID,
    uint256 id,
    string calldata name,
    string calldata slot,
    uint256 form
  ) internal {
    _optionToId[optionID] = id;
    _options[id] = Option(
      Requirement.None,
      form,
      name,
      slot,
      optionID
    );
  }

  function setEthRequirement(uint256 id, uint256 cost) external {
    _options[id].req = Requirement.HasEth;
    _idToEthCost[id] = cost;
  }

  function setLegacyPillRequirement(uint256 id, uint256 reqId) external {
    _options[id].req = Requirement.HasLegacyPill;
    _idToLegacyPillReq[id] = reqId;
    legacyPillToId[reqId] = id;
  }

  function setCollabPillRequirement(uint256 id, uint256 reqId) external {
    _options[id].req = Requirement.HasCollabPill;
    _idToCollabPillReq[id] = reqId;
    collabPillToId[reqId] = id;
  }

  function setTraitRequirement(uint256 id, string calldata trait) external {
    _options[id].req = Requirement.HasTrait;
    _idToTraitReq[id] = trait;
  }

  function setNotTraitRequirement(uint256 id, string calldata trait) external {
    _options[id].req = Requirement.HasNotTrait;
    _idToTraitReq[id] = trait;
  }

  function getCostFromOption(string calldata option)
    external
    view
    returns (uint256)
  {
    uint256 id = _optionToId[option];
    Option memory optionStruct = _options[id];
    if (optionStruct.req != Requirement.HasEth) {
      return 0;
    }
    return _idToEthCost[id];
  }

  function _checkHasEth(uint256 id, uint256 ethValue) internal view {
    require(ethValue >= _idToEthCost[id], "not enough ETH");
  }

  function _checkHasCollabPill(uint256 id, address target) internal view {
    //Could be optimized
    require(
      IToken(_collabPills).balanceOf(target, _idToCollabPillReq[id]) > 0,
      "You do not have the required collab pill"
    );
  }

  function _checkHasLegacyPill(
    uint256 id,
    uint256[] calldata legacyPillId,
    address target
  ) internal view {
    // Could be optimized
    bool found = false;
    for (uint256 index = 0; index < legacyPillId.length && found==false; index++) {
      // TODO: move the balance check/transfer higher up in the function processing
      found = IToken(_legacyPills).balanceOf(target, legacyPillId[index]) > 0 &&
        _idToLegacyPillReq[id] == LegacyPills.getTypeFromId(legacyPillId[index]);
    }
    require(found, "You do not have the required Legacy pill");
  }

  function getStringFromLegacyPill(uint256 pillId) external view returns (string memory) {
    uint256 pillType = LegacyPills.getTypeFromId(pillId);
    uint256 id = legacyPillToId[pillType];
    return getOptionStringFromId(id);
  }
  
  function getStringFromCollabPill(uint256 pillId) external view returns (string memory) {
    return getOptionStringFromId(collabPillToId[pillId]);
  }

  function _checkHasTrait(uint256 id, string[] calldata options) internal view {
    require(
      _findTrait(id, options) == true,
      "You don't have the correct trait"
    );
  }

  function _checkHasNotTrait(uint256 id, string[] calldata options)
    internal
    view
  {
    require(_findTrait(id, options) == false, "You have an incompatible trait");
  }

  function _findTrait(uint256 id, string[] calldata options)
    internal
    view
    returns (bool traitFound)
  {
    string memory trait = _idToTraitReq[id];
    for (uint256 i = 0; i < 5 && !traitFound; i++) {
      traitFound = _compareMem2Call(trait, options[i]);
    }
  }
}

