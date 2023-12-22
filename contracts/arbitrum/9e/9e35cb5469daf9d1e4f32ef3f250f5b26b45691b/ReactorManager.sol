// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IRealm.sol";
import "./IReactor.sol";
import "./IStructureStaker.sol";
import "./IRealmLock.sol";

import "./ManagerModifier.sol";

contract ReactorManager is ReentrancyGuard, Pausable, ManagerModifier {
  //=======================================
  // Immutables
  //=======================================
  IRealm public immutable REALM;
  IReactor public immutable REACTOR;
  IStructureStaker public immutable STRUCTURE_STAKER;
  IRealmLock public immutable REALM_LOCK;

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
    address _realmLock
  ) ManagerModifier(_manager) {
    REALM = IRealm(_realm);
    REACTOR = IReactor(_reactor);
    STRUCTURE_STAKER = IStructureStaker(_structureStaker);
    REALM_LOCK = IRealmLock(_realmLock);
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

    emit ReactorStaked(_realmId, address(REACTOR), _structureId);
  }

  function stakeBatch(
    uint256[] calldata _realmIds,
    uint256[] calldata _structureIds
  ) external nonReentrant whenNotPaused {
    // Set addresses
    address[] memory addresses = new address[](1);
    addresses[0] = address(REACTOR);

    // Stake
    STRUCTURE_STAKER.stakeBatchFor(
      msg.sender,
      _realmIds,
      addresses,
      _structureIds
    );

    emit ReactorBatchStaked(_realmIds, addresses, _structureIds);
  }

  function unstake(uint256 _realmId, uint256 _structureId)
    external
    nonReentrant
    whenNotPaused
  {
    // Check if Realm is locked
    require(REALM_LOCK.isUnlocked(_realmId), "ReactorManager: Realm is locked");

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
    uint256 j = 0;
    uint256 length = _realmIds.length;

    // Check if Realm is locked
    for (; j < length; j++) {
      require(
        REALM_LOCK.isUnlocked(_realmIds[j]),
        "ReactorManager: Realm is locked"
      );
    }

    // Set addresses
    address[] memory addresses = new address[](1);
    addresses[0] = address(REACTOR);

    // Unstake
    STRUCTURE_STAKER.unstakeBatchFor(
      msg.sender,
      _realmIds,
      addresses,
      _structureIds
    );

    emit ReactorBatchUnstaked(_realmIds, addresses, _structureIds);
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
}

