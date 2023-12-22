// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IRealm {
  function ownerOf(uint256 _realmId) external view returns (address owner);

  function isApprovedForAll(address owner, address operator)
    external
    returns (bool);

  function realmFeatures(uint256 realmId, uint256 index)
    external
    view
    returns (uint256);
}

interface IManager {
  function isManager(address _addr, uint256 _type) external view returns (bool);
}

interface IData {
  function data(uint256 realmId, uint256 _type) external view returns (uint256);

  function add(
    uint256 _realmId,
    uint256 _type,
    uint256 _amount
  ) external;

  function addToBuildQueue(
    uint256 realmId,
    uint256 queueSlot,
    uint256 _hours
  ) external;
}

contract Farm {
  IRealm public constant REALM =
    IRealm(0x4de95c1E202102E22E801590C51D7B979f167FBB);
  IManager public constant MANAGER =
    IManager(0x4E572433A3Bfa336b6396D13AfC9F69b58252861);
  IData constant DATA = IData(0xAae3A78EA8De1b89C64D5c64A26d5b1FC8F91496);

  uint256 private constant BUILD_TIME = 12 hours;

  uint256[9] private resourceBonus = [2, 6, 7, 11, 12, 14, 17, 20, 23];

  uint256[] public resourceProbability = [40, 50, 60, 70, 80, 85, 90, 94, 97];
  string[9] public resourceNames = [
    "None",
    "Wheat",
    "Corn",
    "Rice",
    "Honey",
    "Tea",
    "Coffee",
    "Chocolate",
    "Wine"
  ];

  uint256[] public dataProbability = [40, 80, 90, 95];

  mapping(uint256 => mapping(uint256 => uint256)) public farms;
  mapping(uint256 => mapping(uint256 => uint256)) public resources;

  mapping(uint256 => uint256) public totalFarms;

  event Built(
    uint256 realmId,
    uint256 farmId,
    uint256 resourceId,
    string resourceName,
    uint256 totalResources,
    uint256 totalFarms
  );
  event ResourceAdded(
    uint256 realmId,
    uint256 amount,
    uint256 resourceId,
    string resourceName,
    uint256 totalResources
  );
  event ResourceRemoved(
    uint256 realmId,
    uint256 amount,
    uint256 resourceId,
    string resourceName,
    uint256 totalResources
  );

  function build(uint256 _realmId, uint256 _queueSlot) external {
    address _owner = REALM.ownerOf(_realmId);

    require(_owner == msg.sender || REALM.isApprovedForAll(_owner, msg.sender));

    DATA.addToBuildQueue(_realmId, _queueSlot, BUILD_TIME);

    uint256 _id = totalFarms[_realmId];
    uint256 _resourceId = _rarity(_realmId, resourceProbability);

    // food
    DATA.add(_realmId, 1, _rarity(_realmId, dataProbability) + 1);

    if (_resourceId > 0) {
      resources[_realmId][_resourceId] += 100 + _bonus(_realmId);

      if (_resourceId > 5) {
        // culture
        DATA.add(_realmId, 3, 1);
      }
    }

    farms[_realmId][_id] = _resourceId;
    totalFarms[_realmId]++;

    emit Built(
      _realmId,
      _id,
      _resourceId,
      resourceNames[_resourceId],
      resources[_realmId][_resourceId],
      totalFarms[_realmId]
    );
  }

  function add(
    uint256 _realmId,
    uint256 _resourceId,
    uint256 _amount
  ) external {
    require(MANAGER.isManager(msg.sender, 1));

    resources[_realmId][_resourceId] += _amount;

    emit ResourceAdded(
      _realmId,
      _amount,
      _resourceId,
      resourceNames[_resourceId],
      resources[_realmId][_resourceId]
    );
  }

  function remove(
    uint256 _realmId,
    uint256 _resourceId,
    uint256 _amount
  ) external {
    require(
      _amount <= resources[_realmId][_resourceId],
      "Not enough resources"
    );

    address _owner = REALM.ownerOf(_realmId);

    require(
      MANAGER.isManager(msg.sender, 1) ||
        _owner == msg.sender ||
        REALM.isApprovedForAll(_owner, msg.sender)
    );

    resources[_realmId][_resourceId] -= _amount;

    emit ResourceRemoved(
      _realmId,
      _amount,
      _resourceId,
      resourceNames[_resourceId],
      resources[_realmId][_resourceId]
    );
  }

  function _bonus(uint256 _realmId) internal view returns (uint256) {
    uint256 _feature1 = REALM.realmFeatures(_realmId, 0);
    uint256 _feature2 = REALM.realmFeatures(_realmId, 1);
    uint256 _feature3 = REALM.realmFeatures(_realmId, 2);
    uint256 _b;

    for (uint256 i; i < resourceBonus.length; i++) {
      if (
        _feature1 == resourceBonus[i] ||
        _feature2 == resourceBonus[i] ||
        _feature3 == resourceBonus[i]
      ) {
        _b += 1;
      }
    }

    return _b;
  }

  function _rarity(uint256 _salt, uint256[] memory probability)
    internal
    view
    returns (uint256)
  {
    uint256 _rand = uint256(
      keccak256(abi.encodePacked(block.number, block.timestamp, _salt))
    ) % 100;

    uint256 j = 0;
    for (; j < probability.length; j++) {
      if (_rand <= probability[j]) {
        break;
      }
    }
    return j;
  }
}

