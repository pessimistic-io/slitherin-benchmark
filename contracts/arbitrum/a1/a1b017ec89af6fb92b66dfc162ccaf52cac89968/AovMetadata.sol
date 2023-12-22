// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./Strings.sol";
import "./Base64.sol";

import "./IAovMetadata.sol";
import "./IAdventurerData.sol";

import "./ManagerModifier.sol";

contract AovMetadata is IAovMetadata, ManagerModifier {
  using Strings for uint256;
  //=======================================
  // Immutables
  //=======================================
  IAdventurerData public immutable ADVENTURER_DATA;

  //=======================================
  // Strings
  //=======================================
  string public baseURI;

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager, address _adventurerData)
    ManagerModifier(_manager)
  {
    ADVENTURER_DATA = IAdventurerData(_adventurerData);
  }

  //=======================================
  // External
  //=======================================
  function uri(address _addr, uint256 _tokenId)
    external
    view
    override
    returns (string memory)
  {
    uint256[] memory aov = _aovData(_addr, _tokenId);

    string memory json = string(
      abi.encodePacked(
        'data:application/json;utf8,{"name": "AoV ',
        Strings.toString(_tokenId),
        '"',
        ', "description": "The Realmverse awaits. Adventurers of the Void are the first inhabitants of the Realmverse and are ready to explore, quest, battle and much more.", "image": "',
        abi.encodePacked(baseURI, Strings.toString(aov[1]), ".jpeg"),
        '"',
        ',"attributes":',
        _attributes(_addr, _tokenId, aov),
        "}"
      )
    );

    return json;
  }

  //=======================================
  // Admin
  //=======================================
  function setBaseURI(string calldata _baseURI) external onlyAdmin {
    baseURI = _baseURI;
  }

  //=======================================
  // Internal
  //=======================================
  function _attributes(
    address _addr,
    uint256 _tokenId,
    uint256[] memory _aov
  ) internal view returns (string memory) {
    string[29] memory _parts;

    uint256[] memory base = _baseData(_addr, _tokenId);

    _parts[0] = '[{ "trait_type": "Transcendence Level", "value": "';
    _parts[1] = Strings.toString(_aov[0]);
    _parts[2] = '" }, { "trait_type": "Class", "value": "';
    _parts[3] = _class(_aov[2]);
    _parts[4] = '" }, { "trait_type": "Profession", "value": "';
    _parts[5] = _profession(_aov[3]);
    _parts[6] = '" }, { "trait_type": "XP", "value": "';
    _parts[7] = Strings.toString(base[0]);
    _parts[8] = '" }, { "trait_type": "HP", "value": "';
    _parts[9] = Strings.toString(base[1]);
    _parts[10] = '" }, { "trait_type": "Strength", "value": "';
    _parts[11] = Strings.toString(base[2]);
    _parts[12] = '" }, { "trait_type": "Dexterity", "value": "';
    _parts[13] = Strings.toString(base[3]);
    _parts[14] = '" }, { "trait_type": "Constitution", "value": "';
    _parts[15] = Strings.toString(base[4]);
    _parts[16] = '" }, { "trait_type": "Intelligence", "value": "';
    _parts[17] = Strings.toString(base[5]);
    _parts[18] = '" }, { "trait_type": "Wisdom", "value": "';
    _parts[19] = Strings.toString(base[6]);
    _parts[20] = '" }, { "trait_type": "Charisma", "value": "';
    _parts[21] = Strings.toString(base[7]);
    _parts[22] = '" }, { "trait_type": "Name", "value": "';
    _parts[23] = "Forgotten";
    _parts[24] = '" }, { "trait_type": "Origin", "value": "';
    _parts[25] = "Unknown";
    _parts[26] = '" }, { "trait_type": "Inheritance", "value": "';
    _parts[27] = "Undiscovered";
    _parts[28] = '" }]';

    string memory _output = string(
      abi.encodePacked(
        _parts[0],
        _parts[1],
        _parts[2],
        _parts[3],
        _parts[4],
        _parts[5],
        _parts[6]
      )
    );
    _output = string(
      abi.encodePacked(
        _output,
        _parts[7],
        _parts[8],
        _parts[9],
        _parts[10],
        _parts[11],
        _parts[12]
      )
    );
    _output = string(
      abi.encodePacked(
        _output,
        _parts[13],
        _parts[14],
        _parts[15],
        _parts[16],
        _parts[17],
        _parts[18]
      )
    );
    _output = string(
      abi.encodePacked(
        _output,
        _parts[19],
        _parts[20],
        _parts[21],
        _parts[22],
        _parts[23],
        _parts[24]
      )
    );
    _output = string(
      abi.encodePacked(_output, _parts[25], _parts[26], _parts[27], _parts[28])
    );

    return _output;
  }

  function _class(uint256 _classId) internal pure returns (string memory) {
    if (_classId == 1) {
      return "Chaos";
    } else if (_classId == 2) {
      return "Mischief";
    } else {
      return "Tranquility";
    }
  }

  function _profession(uint256 _professionId)
    internal
    pure
    returns (string memory)
  {
    if (_professionId == 1) {
      return "Explorer";
    } else if (_professionId == 2) {
      return "Zealot";
    } else if (_professionId == 3) {
      return "Scientist";
    } else {
      return "No Profession";
    }
  }

  function _baseData(address _addr, uint256 _adventurerId)
    internal
    view
    returns (uint256[] memory)
  {
    return ADVENTURER_DATA.baseProperties(_addr, _adventurerId, 0, 7);
  }

  function _aovData(address _addr, uint256 _adventurerId)
    internal
    view
    returns (uint256[] memory)
  {
    return ADVENTURER_DATA.aovProperties(_addr, _adventurerId, 0, 3);
  }
}

