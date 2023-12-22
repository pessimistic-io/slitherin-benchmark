// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IRealm.sol";
import "./IMagicRefinery.sol";
import "./IStructureStaker.sol";
import "./IRealmLock.sol";

import "./ManagerModifier.sol";

contract MagicRefineryManager is ReentrancyGuard, Pausable, ManagerModifier {
  //=======================================
  // Immutables
  //=======================================
  IRealm public immutable REALM;
  IMagicRefinery public immutable REFINERY;
  IStructureStaker public immutable STRUCTURE_STAKER;

  //=======================================
  // ReamLock
  //=======================================
  IRealmLock public realmLock;

  //=======================================
  // Events
  //=======================================
  event MagicRefineryStaked(
    uint256 realmId,
    address structureAddress,
    uint256 structureId
  );
  event MagicRefineryUnstaked(
    uint256 realmId,
    address structureAddress,
    uint256 structureId
  );
  event MagicRefineryBatchStaked(
    uint256[] realmIds,
    address[] structureAddresses,
    uint256[] structureIds
  );
  event MagicRefineryBatchUnstaked(
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
    address _refinery,
    address _structureStaker,
    address _realmLock
  ) ManagerModifier(_manager) {
    REALM = IRealm(_realm);
    REFINERY = IMagicRefinery(_refinery);
    STRUCTURE_STAKER = IStructureStaker(_structureStaker);

    realmLock = IRealmLock(_realmLock);
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
      address(REFINERY),
      _structureId
    );

    emit MagicRefineryStaked(_realmId, address(REFINERY), _structureId);
  }

  function stakeBatch(
    uint256[] calldata _realmIds,
    uint256[] calldata _structureIds
  ) external nonReentrant whenNotPaused {
    // Set addresses
    address[] memory addresses = new address[](1);
    addresses[0] = address(REFINERY);

    // Stake
    STRUCTURE_STAKER.stakeBatchFor(
      msg.sender,
      _realmIds,
      addresses,
      _structureIds
    );

    emit MagicRefineryBatchStaked(_realmIds, addresses, _structureIds);
  }

  function unstake(uint256 _realmId, uint256 _structureId)
    external
    nonReentrant
    whenNotPaused
  {
    // Check if Realm is locked
    require(
      realmLock.isUnlocked(_realmId),
      "MagicRefineryManager: Realm is locked"
    );

    // Get StakedAt
    (, , uint256 stakedAt) = STRUCTURE_STAKER.getStaker(
      _realmId,
      address(REFINERY),
      _structureId
    );

    // Check structure is staked to Realm
    require(stakedAt != 0, "MagicRefineryManager: Structure not part of Realm");

    // Unstake
    STRUCTURE_STAKER.unstakeFor(
      msg.sender,
      _realmId,
      address(REFINERY),
      _structureId
    );

    emit MagicRefineryUnstaked(_realmId, address(REFINERY), _structureId);
  }

  function unstakeBatch(
    uint256[] calldata _realmIds,
    uint256[] calldata _structureIds
  ) external nonReentrant whenNotPaused {
    uint256 j = 0;
    uint256 length = _realmIds.length;

    // Check if Realm is locked
    for (; j < length; j++) {
      uint256 realmId = _realmIds[j];

      require(
        realmLock.isUnlocked(realmId),
        "MagicRefineryManager: Realm is locked"
      );

      // Get StakedAt
      (, , uint256 stakedAt) = STRUCTURE_STAKER.getStaker(
        realmId,
        address(REFINERY),
        _structureIds[j]
      );

      // Check structure is staked to Realm
      require(
        stakedAt != 0,
        "MagicRefineryManager: Structure not part of Realm"
      );
    }

    // Set addresses
    address[] memory addresses = new address[](1);
    addresses[0] = address(REFINERY);

    // Unstake
    STRUCTURE_STAKER.unstakeBatchFor(
      msg.sender,
      _realmIds,
      addresses,
      _structureIds
    );

    emit MagicRefineryBatchUnstaked(_realmIds, addresses, _structureIds);
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

