// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IRealm.sol";
import "./ILab.sol";
import "./ICollectible.sol";
import "./IBatchStaker.sol";
import "./ILabStorage.sol";

import "./ManagerModifier.sol";

contract LabMinter is ReentrancyGuard, Pausable, ManagerModifier {
  //=======================================
  // Immutables
  //=======================================
  IRealm public immutable REALM;
  ILab public immutable ENTITY;
  ICollectible public immutable COLLECTIBLE;
  IBatchStaker public immutable BATCH_STAKER;
  ILabStorage public immutable STORAGE;
  address public immutable COLLECTIBLE_HOLDER;

  //=======================================
  // Mappings
  //=======================================
  mapping(uint256 => uint256[]) public collectibleType;
  mapping(uint256 => uint256) public collectibleCost;

  //=======================================
  // Events
  //=======================================
  event Minted(uint256[] realmIds, uint256[] entityIds, uint256[] amounts);
  event Burned(uint256[] realmIds, uint256[] entityIds, uint256[] amounts);
  event CollectiblesUsed(
    uint256 realmId,
    uint256 collectibleId,
    uint256 amount
  );

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _realm,
    address _manager,
    address _collectible,
    address _batchStaker,
    address _entity,
    address _storage,
    address _collectibleHolder
  ) ManagerModifier(_manager) {
    REALM = IRealm(_realm);
    COLLECTIBLE = ICollectible(_collectible);
    BATCH_STAKER = IBatchStaker(_batchStaker);
    ENTITY = ILab(_entity);
    COLLECTIBLE_HOLDER = _collectibleHolder;
    STORAGE = ILabStorage(_storage);

    collectibleType[0] = [20, 21];
    collectibleType[1] = [22, 23];
    collectibleType[2] = [24, 25];
    collectibleType[3] = [26];
    collectibleType[4] = [27];
    collectibleType[5] = [28];
    collectibleType[6] = [29];

    collectibleCost[0] = 10;
    collectibleCost[1] = 10;
    collectibleCost[2] = 10;
    collectibleCost[3] = 10;
    collectibleCost[4] = 10;
    collectibleCost[5] = 10;
    collectibleCost[6] = 10;
  }

  //=======================================
  // External
  //=======================================
  function mint(
    uint256[] calldata _realmIds,
    uint256[] calldata _collectibleIds,
    uint256[] calldata _entityIds,
    uint256[] calldata _quantities
  ) external nonReentrant whenNotPaused {
    for (uint256 j = 0; j < _entityIds.length; j++) {
      uint256 realmId = _realmIds[j];
      uint256 collectibleId = _collectibleIds[j];
      uint256 entityId = _entityIds[j];
      uint256 desiredQuantity = _quantities[j];

      // Check if Realm owner
      require(
        REALM.ownerOf(realmId) == msg.sender,
        "LabMinter: Must be Realm owner"
      );

      // Check collectibleId is valid
      _checkCollectibleType(entityId, collectibleId);

      // Mint
      ENTITY.mintFor(msg.sender, entityId, desiredQuantity);

      uint256 collectibleAmount = collectibleCost[entityId] * desiredQuantity;

      // Burn collectibles
      COLLECTIBLE.safeTransferFrom(
        msg.sender,
        COLLECTIBLE_HOLDER,
        collectibleId,
        collectibleAmount,
        ""
      );

      emit CollectiblesUsed(realmId, collectibleId, collectibleAmount);
    }

    emit Minted(_realmIds, _entityIds, _quantities);
  }

  function burn(
    uint256[][] calldata _realmIds,
    uint256[][] calldata _entityIds,
    uint256[][] calldata _amounts
  ) external nonReentrant whenNotPaused {
    for (uint256 j = 0; j < _realmIds.length; j++) {
      uint256[] memory realmIds = _realmIds[j];
      uint256[] memory entityIds = _entityIds[j];
      uint256[] memory amounts = _amounts[j];

      // Burn entities
      ENTITY.burnBatchFor(msg.sender, entityIds, amounts);

      // Add labs to realm
      STORAGE.set(realmIds, entityIds, amounts);

      emit Burned(realmIds, entityIds, amounts);
    }
  }

  //=======================================
  // Admin
  //=======================================
  function pause() external onlyAdmin {
    _pause();
  }

  function unpause() external onlyAdmin {
    _unpause();
  }

  function updateCollectibleCost(
    uint256[] calldata _values
  ) external onlyAdmin {
    collectibleCost[0] = _values[0];
    collectibleCost[1] = _values[1];
    collectibleCost[2] = _values[2];
    collectibleCost[3] = _values[3];
    collectibleCost[4] = _values[4];
    collectibleCost[5] = _values[5];
    collectibleCost[6] = _values[6];
  }

  function updateCollectibleType(
    uint256[][] calldata _values
  ) external onlyAdmin {
    collectibleType[0] = _values[0];
    collectibleType[1] = _values[1];
    collectibleType[2] = _values[2];
    collectibleType[3] = _values[3];
    collectibleType[4] = _values[4];
    collectibleType[5] = _values[5];
    collectibleType[6] = _values[6];
  }

  //=======================================
  // Internal
  //=======================================
  function _checkCollectibleType(
    uint256 _entityId,
    uint256 _collectibleId
  ) internal view {
    bool invalid;

    for (uint256 j = 0; j < collectibleType[_entityId].length; j++) {
      // Check collectibleId matches collectible IDs
      if (_collectibleId == collectibleType[_entityId][j]) {
        invalid = false;
        break;
      }

      invalid = true;
    }

    require(
      !invalid,
      "LabMinter: Collectible doesn't match entity requirements"
    );
  }
}

