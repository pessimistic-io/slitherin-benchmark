// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./ERC721A.sol";

import "./IRealm.sol";
import "./IData.sol";
import "./IStructure.sol";
import "./IAdventurerData.sol";
import "./IParticle.sol";
import "./IParticleTracker.sol";
import "./IPopulation.sol";
import "./IAdventurerGateway.sol";

import "./ManagerModifier.sol";

contract ParticleMinter is ManagerModifier, ReentrancyGuard, Pausable {
  //=======================================
  // Immutables
  //=======================================
  IRealm public immutable REALM;
  IData public immutable DATA;
  IStructure public immutable STRUCTURE;
  IAdventurerData public immutable ADVENTURER_DATA;
  IParticle public immutable PARTICLE;
  IParticleTracker public immutable PARTICLE_TRACKER;
  IPopulation public immutable POPULATION;
  IAdventurerGateway public immutable GATEWAY;

  //=======================================
  // Uints
  //=======================================
  uint256 public adventurerBaseParticle;
  uint256 public realmerBaseParticle;
  uint256 public professionBonus;
  uint256 public maxCaptureTime;
  uint256 public explorerWeight;

  //=======================================
  // Events
  //=======================================
  event Init(uint256 realmId, address addr, uint256 adventurerId);
  event Captured(
    uint256 realmId,
    address addr,
    uint256 adventurerId,
    uint256 adventurerParticles,
    uint256 realmerParticles
  );

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _realm,
    address _manager,
    address _data,
    address _structure,
    address _adventurerData,
    address _particle,
    address _tracker,
    address _population,
    address _gateway,
    uint256 _adventurerBaseParticle,
    uint256 _realmerBaseParticle,
    uint256 _professionBonus
  ) ManagerModifier(_manager) {
    REALM = IRealm(_realm);
    DATA = IData(_data);
    STRUCTURE = IStructure(_structure);
    ADVENTURER_DATA = IAdventurerData(_adventurerData);
    PARTICLE = IParticle(_particle);
    PARTICLE_TRACKER = IParticleTracker(_tracker);
    POPULATION = IPopulation(_population);
    GATEWAY = IAdventurerGateway(_gateway);

    adventurerBaseParticle = _adventurerBaseParticle;
    realmerBaseParticle = _realmerBaseParticle;
    professionBonus = _professionBonus;
    maxCaptureTime = 3600 * 24 * 7;
    explorerWeight = 10;
  }

  //=======================================
  // External
  //=======================================

  // With realmIds
  function capture(
    address[] calldata _addresses,
    uint256[] calldata _adventurerIds,
    bytes32[][] calldata _proofs,
    uint256[] calldata _realmIds
  ) external nonReentrant whenNotPaused {
    for (uint256 j = 0; j < _adventurerIds.length; j++) {
      uint256 realmId = _realmIds[j];
      address addr = _addresses[j];
      uint256 adventurerId = _adventurerIds[j];

      // Check validity of address
      _checkAddress(addr, _proofs[j]);

      // Get current realm exploring
      (uint256 currentRealmId, bool isRealmSet) = PARTICLE_TRACKER.currentRealm(
        addr,
        adventurerId
      );

      // Initialize if realm is not set
      if (!isRealmSet) {
        // Check sender owns adventurer
        require(
          ERC721A(addr).ownerOf(adventurerId) == msg.sender,
          "ParticleMinter: You do not own Adventurer"
        );

        // Check realm exists
        REALM.ownerOf(realmId);

        // Check if realm has enough population
        _checkPopulation(realmId);

        // Set timer
        PARTICLE_TRACKER.setTimer(addr, adventurerId);

        // Add explorer
        PARTICLE_TRACKER.addExplorer(
          realmId,
          addr,
          adventurerId,
          explorerWeight
        );

        emit Init(realmId, addr, adventurerId);

        continue;
      }

      // Capture
      _capture(addr, adventurerId, currentRealmId);

      // Check if realm has enough population
      _checkPopulation(realmId);

      // Remove explorer
      PARTICLE_TRACKER.removeExplorer(
        currentRealmId,
        addr,
        adventurerId,
        explorerWeight
      );

      // Add explorer
      PARTICLE_TRACKER.addExplorer(realmId, addr, adventurerId, explorerWeight);
    }
  }

  function capture(
    address[] calldata _addresses,
    uint256[] calldata _adventurerIds,
    bytes32[][] calldata _proofs
  ) external nonReentrant whenNotPaused {
    for (uint256 j = 0; j < _adventurerIds.length; j++) {
      address addr = _addresses[j];
      uint256 adventurerId = _adventurerIds[j];

      // Check validity of address
      _checkAddress(addr, _proofs[j]);

      // Get current realm exploring
      (uint256 currentRealmId, bool isRealmSet) = PARTICLE_TRACKER.currentRealm(
        addr,
        adventurerId
      );

      // Check current realm has been set
      require(
        isRealmSet,
        "ParticleMinter: You must choose a realm to explore first"
      );

      // Capture
      _capture(addr, adventurerId, currentRealmId);
    }
  }

  function getElapsedTime(address _addr, uint256 _adventurerId)
    external
    view
    returns (uint256)
  {
    return _elapsedTime(_addr, _adventurerId);
  }

  function particlesAccumulatedForRealmer(
    uint256 _realmId,
    address _addr,
    uint256 _adventurerId
  ) external view returns (uint256) {
    return _totalParticlesForRealmer(_realmId, _addr, _adventurerId);
  }

  function particlesAccumulatedForAdventurer(
    address _addr,
    uint256 _adventurerId
  ) external view returns (uint256) {
    return _totalParticlesForAdventurer(_addr, _adventurerId);
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

  function updateAdventurerBaseParticle(uint256 _value) external onlyAdmin {
    adventurerBaseParticle = _value;
  }

  function updateRealmerBaseParticle(uint256 _value) external onlyAdmin {
    realmerBaseParticle = _value;
  }

  function updateProfessionBonus(uint256 _value) external onlyAdmin {
    professionBonus = _value;
  }

  function updateMaxCaptureTime(uint256 _value) external onlyAdmin {
    maxCaptureTime = _value;
  }

  function updateExplorerWeight(uint256 _value) external onlyAdmin {
    explorerWeight = _value;
  }

  //=======================================
  // Internal
  //=======================================
  function _capture(
    address _addr,
    uint256 _adventurerId,
    uint256 _realmId
  ) internal {
    // Check sender owns adventurer
    require(
      ERC721A(_addr).ownerOf(_adventurerId) == msg.sender,
      "ParticleMinter: You do not own Adventurer"
    );

    // Get total particles for adventurer
    uint256 adventurerParticles = _totalParticlesForAdventurer(
      _addr,
      _adventurerId
    );

    // Mint particles for Adventurer
    PARTICLE.mintFor(msg.sender, adventurerParticles);

    // Get total particles for realmer
    uint256 realmerParticles = _totalParticlesForRealmer(
      _realmId,
      _addr,
      _adventurerId
    );

    // Mint particles for Realmer
    PARTICLE.mintFor(_realmOwner(_realmId), realmerParticles);

    // Set timer
    PARTICLE_TRACKER.setTimer(_addr, _adventurerId);

    emit Captured(
      _realmId,
      _addr,
      _adventurerId,
      adventurerParticles,
      realmerParticles
    );
  }

  function _totalResources(uint256 _realmId) internal view returns (uint256) {
    uint256 total = DATA.data(_realmId, 0) +
      DATA.data(_realmId, 1) +
      DATA.data(_realmId, 3) +
      DATA.data(_realmId, 5) +
      STRUCTURE.data(_realmId, 0) +
      STRUCTURE.data(_realmId, 1) +
      STRUCTURE.data(_realmId, 2) +
      STRUCTURE.data(_realmId, 3);

    // Check if total is zero, default returned should be 1
    if (total == 0) return 1;

    return total;
  }

  function _getAdventurerData(address _addr, uint256 _adventurerId)
    internal
    view
    returns (uint256[] memory)
  {
    // Make sure these slots didn't change
    return ADVENTURER_DATA.aovProperties(_addr, _adventurerId, 0, 3);
  }

  function _totalParticlesForAdventurer(address _addr, uint256 _adventurerId)
    internal
    view
    returns (uint256)
  {
    uint256 particles = ADVENTURER_DATA.aov(_addr, _adventurerId, 0) *
      adventurerBaseParticle;

    // Check if profession is Explorer
    if (ADVENTURER_DATA.aov(_addr, _adventurerId, 3) == 1) {
      particles += professionBonus;
    }

    return _elapsedTime(_addr, _adventurerId) * (particles / 24 / 60 / 60);
  }

  function _totalParticlesForRealmer(
    uint256 _realmId,
    address _addr,
    uint256 _adventurerId
  ) internal view returns (uint256) {
    uint256 particlesPerSecond = (realmerBaseParticle *
      _totalResources(_realmId)) /
      24 /
      60 /
      60;

    return _elapsedTime(_addr, _adventurerId) * particlesPerSecond;
  }

  function _elapsedTime(address _addr, uint256 _adventurerId)
    internal
    view
    returns (uint256)
  {
    // Calculate elapsed time
    uint256 elapsedTime = block.timestamp -
      PARTICLE_TRACKER.timer(_addr, _adventurerId);

    // Check elapsed time is less than max capture time
    if (elapsedTime > maxCaptureTime) {
      return maxCaptureTime;
    }

    return elapsedTime;
  }

  function _realmOwner(uint256 _realmId) internal view returns (address) {
    return REALM.ownerOf(_realmId);
  }

  function _checkPopulation(uint256 _realmId) internal view {
    require(
      PARTICLE_TRACKER.getExplorerCount(_realmId) <
        POPULATION.getPopulation(_realmId),
      "ParticleMinter: Max Realm population reached"
    );
  }

  function _checkAddress(address _addr, bytes32[] calldata _proof)
    internal
    view
  {
    // Verify address
    GATEWAY.checkAddress(_addr, _proof);
  }
}

