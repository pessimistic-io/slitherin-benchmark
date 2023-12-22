// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IRealm.sol";
import "./IMonument.sol";
import "./IRealmLock.sol";
import "./IBatchBurnableStaker.sol";

import "./ManagerModifier.sol";

contract MonumentStaker is ReentrancyGuard, Pausable, ManagerModifier {
  //=======================================
  // Immutables
  //=======================================
  IMonument public immutable ENTITY;
  IBatchBurnableStaker public immutable BATCH_STAKER;

  //=======================================
  // RealmLock
  //=======================================
  IRealmLock public realmLock;

  //=======================================
  // Events
  //=======================================
  event StakedEntity(
    address addr,
    uint256[] realmIds,
    uint256[] entityIds,
    uint256[] amounts
  );
  event UnstakedEntity(
    address addr,
    uint256[] realmIds,
    uint256[] entityIds,
    uint256[] amounts
  );

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _manager,
    address _batchStaker,
    address _entity,
    address _realmLock
  ) ManagerModifier(_manager) {
    BATCH_STAKER = IBatchBurnableStaker(_batchStaker);
    ENTITY = IMonument(_entity);

    realmLock = IRealmLock(_realmLock);
  }

  //=======================================
  // External
  //=======================================
  function stakeBatch(
    uint256[][] calldata _realmIds,
    uint256[][] calldata _entityIds,
    uint256[][] calldata _amounts
  ) external nonReentrant whenNotPaused {
    for (uint256 j = 0; j < _realmIds.length; j++) {
      uint256[] memory realmIds = _realmIds[j];
      uint256[] memory entityIds = _entityIds[j];
      uint256[] memory amounts = _amounts[j];

      BATCH_STAKER.stakeBatchFor(
        msg.sender,
        address(ENTITY),
        realmIds,
        entityIds,
        amounts
      );

      emit StakedEntity(address(ENTITY), realmIds, entityIds, amounts);
    }
  }

  function unstakeBatch(
    uint256[][] calldata _realmIds,
    uint256[][] calldata _entityIds,
    uint256[][] calldata _amounts
  ) external nonReentrant whenNotPaused {
    for (uint256 j = 0; j < _realmIds.length; j++) {
      uint256[] memory realmIds = _realmIds[j];

      for (uint256 i = 0; i < realmIds.length; i++) {
        // Check if Realm is locked
        require(
          realmLock.isUnlocked(realmIds[i]),
          "EntityMinter: Realm is locked"
        );
      }

      uint256[] memory entityIds = _entityIds[j];
      uint256[] memory amounts = _amounts[j];

      BATCH_STAKER.unstakeBatchFor(
        msg.sender,
        address(ENTITY),
        realmIds,
        entityIds,
        amounts
      );

      emit UnstakedEntity(address(ENTITY), realmIds, entityIds, amounts);
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

  function updateRealmLock(address _realmLock) external onlyAdmin {
    realmLock = IRealmLock(_realmLock);
  }
}

