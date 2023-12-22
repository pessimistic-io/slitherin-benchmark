// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IRealm.sol";
import "./IReactor.sol";
import "./IStructureStaker.sol";
import "./IRealmLock.sol";
import "./IProduction.sol";

import "./ManagerModifier.sol";

contract ReactorManager is ReentrancyGuard, Pausable, ManagerModifier {
  //=======================================
  // Immutables
  //=======================================
  IRealm public immutable REALM;
  IReactor public immutable REACTOR;
  IStructureStaker public immutable STRUCTURE_STAKER;
  IProduction public immutable PRODUCTION;

  //=======================================
  // ReamLock
  //=======================================
  IRealmLock public realmLock;

  //=======================================
  // Arrays
  //=======================================
  address[] public reactorAddress;

  //=======================================
  // Events
  //=======================================
  event ReactorStaked(
    uint256 realmId,
    address structureAddress,
    uint256 structureId
  );
  event ReactorUnstaked(
    uint256 realmId,
    address structureAddress,
    uint256 structureId
  );
  event ReactorBatchStaked(
    uint256[] realmIds,
    address[] structureAddresses,
    uint256[] structureIds
  );
  event ReactorBatchUnstaked(
    uint256[] realmIds,
    address[] structureAddresses,
    uint256[] structureIds
  );

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _realm,
    address _manager,
    address _reactor,
    address _structureStaker,
    address _realmLock,
    address _production
  ) ManagerModifier(_manager) {
    REALM = IRealm(_realm);
    REACTOR = IReactor(_reactor);
    STRUCTURE_STAKER = IStructureStaker(_structureStaker);
    PRODUCTION = IProduction(_production);

    realmLock = IRealmLock(_realmLock);

    reactorAddress = [_reactor];
  }

  //=======================================
  // External
  //=======================================
  function stake(uint256 _realmId, uint256 _structureId)
    external
    nonReentrant
    whenNotPaused
  {
    // Stake
    STRUCTURE_STAKER.stakeFor(
      msg.sender,
      _realmId,
      address(REACTOR),
      _structureId
    );

    // Reset production
    PRODUCTION.setProduction(_realmId);

    emit ReactorStaked(_realmId, address(REACTOR), _structureId);
  }

  function stakeBatch(
    uint256[] calldata _realmIds,
    uint256[] calldata _structureIds
  ) external nonReentrant whenNotPaused {
    // Stake
    STRUCTURE_STAKER.stakeBatchFor(
      msg.sender,
      _realmIds,
      reactorAddress,
      _structureIds
    );

    // Reset production
    for (uint256 j = 0; j < _realmIds.length; j++) {
      PRODUCTION.setProduction(_realmIds[j]);
    }

    emit ReactorBatchStaked(_realmIds, reactorAddress, _structureIds);
  }

  function unstake(uint256 _realmId, uint256 _structureId)
    external
    nonReentrant
    whenNotPaused
  {
    // Check if Realm is locked
    require(realmLock.isUnlocked(_realmId), "ReactorManager: Realm is locked");

    // Unstake
    STRUCTURE_STAKER.unstakeFor(
      msg.sender,
      _realmId,
      address(REACTOR),
      _structureId
    );

    emit ReactorUnstaked(_realmId, address(REACTOR), _structureId);
  }

  function unstakeBatch(
    uint256[] calldata _realmIds,
    uint256[] calldata _structureIds
  ) external nonReentrant whenNotPaused {
    // Check if Realm is locked
    for (uint256 j = 0; j < _realmIds.length; j++) {
      require(
        realmLock.isUnlocked(_realmIds[j]),
        "ReactorManager: Realm is locked"
      );
    }

    // Unstake
    STRUCTURE_STAKER.unstakeBatchFor(
      msg.sender,
      _realmIds,
      reactorAddress,
      _structureIds
    );

    emit ReactorBatchUnstaked(_realmIds, reactorAddress, _structureIds);
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

