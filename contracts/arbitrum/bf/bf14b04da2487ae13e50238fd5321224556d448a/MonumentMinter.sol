// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IRealm.sol";
import "./IMonument.sol";
import "./IRealmLock.sol";
import "./ICollectible.sol";
import "./IBatchStaker.sol";
import "./IEntityTimer.sol";

import "./ManagerModifier.sol";

contract MonumentMinter is ReentrancyGuard, Pausable, ManagerModifier {
  //=======================================
  // Immutables
  //=======================================
  IRealm public immutable REALM;
  IMonument public immutable ENTITY;
  ICollectible public immutable COLLECTIBLE;
  IBatchStaker public immutable BATCH_STAKER;
  IEntityTimer public immutable TIMER;
  address public immutable COLLECTIBLE_HOLDER;

  //=======================================
  // RealmLock
  //=======================================
  IRealmLock public realmLock;

  //=======================================
  // Uintss
  //=======================================
  uint256 public maxEntities = 3;

  //=======================================
  // Arrays
  //=======================================
  uint256[] public requirements;
  uint256[] public requirementAmounts;

  //=======================================
  // Mappings
  //=======================================
  mapping(uint256 => uint256[]) public collectibleType;
  mapping(uint256 => uint256) public buildHours;
  mapping(uint256 => uint256) public collectibleCost;

  //=======================================
  // Events
  //=======================================
  event Minted(uint256 realmId, uint256 entityId, uint256 quantity);
  event CollectiblesUsed(
    uint256 realmId,
    uint256 collectibleId,
    uint256 amount
  );
  event StakedEntity(
    uint256 realmId,
    address addr,
    uint256[] entityIds,
    uint256[] amounts
  );
  event UnstakedEntity(
    uint256 realmId,
    address addr,
    uint256[] entityIds,
    uint256[] amounts
  );

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _realm,
    address _manager,
    address _collectible,
    address _batchStaker,
    address _timer,
    address _entity,
    address _realmLock,
    address _collectibleHolder,
    uint256[][] memory _collectibleType,
    uint256[] memory _requirements,
    uint256[] memory _requirementAmounts
  ) ManagerModifier(_manager) {
    REALM = IRealm(_realm);
    COLLECTIBLE = ICollectible(_collectible);
    BATCH_STAKER = IBatchStaker(_batchStaker);
    TIMER = IEntityTimer(_timer);
    ENTITY = IMonument(_entity);
    COLLECTIBLE_HOLDER = _collectibleHolder;

    realmLock = IRealmLock(_realmLock);

    collectibleType[0] = _collectibleType[0];
    collectibleType[1] = _collectibleType[1];
    collectibleType[2] = _collectibleType[2];
    collectibleType[3] = _collectibleType[3];
    collectibleType[4] = _collectibleType[4];
    collectibleType[5] = _collectibleType[5];
    collectibleType[6] = _collectibleType[6];

    requirements = _requirements;
    requirementAmounts = _requirementAmounts;

    buildHours[0] = 12;
    buildHours[1] = 12;
    buildHours[2] = 24;
    buildHours[3] = 24;
    buildHours[4] = 36;
    buildHours[5] = 36;
    buildHours[6] = 48;

    collectibleCost[0] = 7;
    collectibleCost[1] = 7;
    collectibleCost[2] = 7;
    collectibleCost[3] = 7;
    collectibleCost[4] = 6;
    collectibleCost[5] = 6;
    collectibleCost[6] = 5;

    _pause();
  }

  //=======================================
  // External
  //=======================================
  function mint(
    uint256 _realmId,
    uint256[] calldata _collectibleIds,
    uint256[] calldata _entityIds,
    uint256[] calldata _quantities
  ) external nonReentrant whenNotPaused {
    // Check if Realm owner
    require(
      REALM.ownerOf(_realmId) == msg.sender,
      "EntityMinter: Must be Realm owner"
    );

    uint256 totalQuantity;
    uint256 totalHours;

    for (uint256 j = 0; j < _entityIds.length; j++) {
      uint256 collectibleId = _collectibleIds[j];
      uint256 entityId = _entityIds[j];
      uint256 desiredQuantity = _quantities[j];

      // Check collectibleId is prime collectible
      _checkCollectibleType(entityId, collectibleId);

      // Check requirements
      _checkRequirements(_realmId, entityId);

      // Mint
      _mint(_realmId, entityId, desiredQuantity);

      // Add to quantity
      totalQuantity = totalQuantity + desiredQuantity;

      // Add total hours
      totalHours = totalHours + (buildHours[entityId] * desiredQuantity);

      uint256 collectibleAmount = collectibleCost[entityId] * desiredQuantity;

      // Burn collectibles
      COLLECTIBLE.safeTransferFrom(
        msg.sender,
        COLLECTIBLE_HOLDER,
        collectibleId,
        collectibleAmount,
        ""
      );

      emit CollectiblesUsed(_realmId, collectibleId, collectibleAmount);
    }

    // Check if totalQuantity is below max entities
    require(
      totalQuantity <= maxEntities,
      "EntityMinter: Max entities per transaction reached"
    );

    // Build
    TIMER.build(_realmId, totalHours);
  }

  function stakeBatch(
    uint256[] calldata _realmIds,
    uint256[][] calldata _entityIds,
    uint256[][] calldata _amounts
  ) external nonReentrant whenNotPaused {
    for (uint256 j = 0; j < _realmIds.length; j++) {
      uint256 realmId = _realmIds[j];
      uint256[] memory entityIds = _entityIds[j];
      uint256[] memory amounts = _amounts[j];

      BATCH_STAKER.stakeBatchFor(
        msg.sender,
        address(ENTITY),
        realmId,
        entityIds,
        amounts
      );

      emit StakedEntity(realmId, address(ENTITY), entityIds, amounts);
    }
  }

  function unstakeBatch(
    uint256[] calldata _realmIds,
    uint256[][] calldata _entityIds,
    uint256[][] calldata _amounts
  ) external nonReentrant whenNotPaused {
    for (uint256 j = 0; j < _realmIds.length; j++) {
      uint256 realmId = _realmIds[j];

      // Check if Realm is locked
      require(realmLock.isUnlocked(realmId), "EntityMinter: Realm is locked");

      uint256[] memory entityIds = _entityIds[j];
      uint256[] memory amounts = _amounts[j];

      BATCH_STAKER.unstakeBatchFor(
        msg.sender,
        address(ENTITY),
        realmId,
        entityIds,
        amounts
      );

      emit UnstakedEntity(realmId, address(ENTITY), entityIds, amounts);
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

  function updateCollectibleCost(uint256[] calldata _values)
    external
    onlyAdmin
  {
    collectibleCost[0] = _values[0];
    collectibleCost[1] = _values[1];
    collectibleCost[2] = _values[2];
    collectibleCost[3] = _values[3];
    collectibleCost[4] = _values[4];
    collectibleCost[5] = _values[5];
    collectibleCost[6] = _values[6];
  }

  function updateMaxEntities(uint256 _maxEntities) external onlyAdmin {
    maxEntities = _maxEntities;
  }

  function updateBuildHours(uint256[] calldata _values) external onlyAdmin {
    buildHours[0] = _values[0];
    buildHours[1] = _values[1];
    buildHours[2] = _values[2];
    buildHours[3] = _values[3];
    buildHours[4] = _values[4];
    buildHours[5] = _values[5];
    buildHours[6] = _values[6];
  }

  function updateRealmLock(address _realmLock) external onlyAdmin {
    realmLock = IRealmLock(_realmLock);
  }

  function updateRequirements(uint256[] calldata _requirements)
    external
    onlyAdmin
  {
    requirements = _requirements;
  }

  function updateCollectibleType(uint256[][] calldata _values)
    external
    onlyAdmin
  {
    collectibleType[0] = _values[0];
    collectibleType[1] = _values[1];
    collectibleType[2] = _values[2];
    collectibleType[3] = _values[3];
    collectibleType[4] = _values[4];
    collectibleType[5] = _values[5];
    collectibleType[6] = _values[6];
  }

  function updateRequirementAmounts(uint256[] calldata _requirementAmounts)
    external
    onlyAdmin
  {
    requirementAmounts = _requirementAmounts;
  }

  //=======================================
  // Internal
  //=======================================
  function _checkRequirements(uint256 _realmId, uint256 _entityId)
    internal
    view
  {
    // Town does not require any staked entities
    if (_entityId == 0) return;

    // Check they have right amount of staked entities
    require(
      BATCH_STAKER.hasStaked(
        _realmId,
        address(ENTITY),
        requirements[_entityId],
        requirementAmounts[_entityId]
      ),
      "EntityMinter: Don't have the required entity staked"
    );
  }

  function _checkCollectibleType(uint256 _entityId, uint256 _collectibleId)
    internal
    view
  {
    bool invalid;

    for (uint256 j = 0; j < collectibleType[_entityId].length; j++) {
      // Check collectibleId matches prime collectible IDs
      if (_collectibleId == collectibleType[_entityId][j]) {
        invalid = false;
        break;
      }

      invalid = true;
    }

    require(
      !invalid,
      "EntityMinter: Collectible doesn't match entity requirements"
    );
  }

  function _mint(
    uint256 _realmId,
    uint256 _entityId,
    uint256 _desiredQuantity
  ) internal {
    // Mint
    ENTITY.mintFor(msg.sender, _entityId, _desiredQuantity);

    emit Minted(_realmId, _entityId, _desiredQuantity);
  }
}

