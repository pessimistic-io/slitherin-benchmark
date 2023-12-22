// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IRealm.sol";
import "./IStructureStaker.sol";
import "./IReactor.sol";
import "./ICollectible.sol";
import "./IProduction.sol";

import "./ManagerModifier.sol";

contract CollectibleProducer is ReentrancyGuard, Pausable, ManagerModifier {
  using SafeERC20 for IERC20;

  //=======================================
  // Immutables
  //=======================================
  IRealm public immutable REALM;
  IStructureStaker public immutable STRUCTURE_STAKER;
  IReactor public immutable REACTOR;
  IProduction public immutable PRODUCTION;
  ICollectible public immutable COLLECTIBLE;
  address public immutable VAULT;
  IERC20 public immutable TOKEN;

  //=======================================
  // Uintss
  //=======================================
  uint256 public defaultCooldownAddition;
  uint256 public maxCollectibles;
  uint256 public maxSeconds;

  //=======================================
  // Arrays
  //=======================================
  uint256[] public cooldowns;
  uint256[] public costs;

  //=======================================
  // Mappings
  //=======================================
  mapping(uint256 => mapping(uint256 => bool)) public geos;
  mapping(uint256 => uint256) public exotics;
  mapping(uint256 => uint256) public rarityHolder;

  //=======================================
  // Events
  //=======================================
  event Activated(uint256 realmId);
  event Produced(
    uint256 realmId,
    uint256 collectibleId,
    uint256 quantity,
    uint256 cost
  );

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _realm,
    address _manager,
    address _structureStaker,
    address _reactor,
    address _production,
    address _collectible,
    address _vault,
    address _token,
    uint256 _maxCollectibles,
    uint256 _maxSeconds
  ) ManagerModifier(_manager) {
    REALM = IRealm(_realm);
    STRUCTURE_STAKER = IStructureStaker(_structureStaker);
    REACTOR = IReactor(_reactor);
    PRODUCTION = IProduction(_production);
    COLLECTIBLE = ICollectible(_collectible);
    VAULT = _vault;
    TOKEN = IERC20(_token);

    maxCollectibles = _maxCollectibles;
    maxSeconds = _maxSeconds;

    exotics[0] = 1;
    exotics[1] = 23;
    exotics[2] = 16;
    exotics[3] = 34;

    // Nourishment
    geos[0][0] = true; // Pond
    geos[0][1] = true; // Valley
    geos[0][5] = true; // Canal
    geos[0][7] = true; // Prairie
    geos[0][11] = true; // River
    geos[0][25] = true; // Biosphere
    geos[0][26] = true; // Lagoon
    geos[0][31] = true; // Oasis
    geos[0][32] = true; // Waterfall

    // Aquatic
    geos[1][12] = true; // Sea
    geos[1][14] = true; // Lake
    geos[1][20] = true; // Fjord
    geos[1][23] = true; // Ocean
    geos[1][13] = true; // Cove
    geos[1][2] = true; // Gulf
    geos[1][17] = true; // Bay
    geos[1][33] = true; // Reef

    // Technological
    geos[2][16] = true; // Tundra
    geos[2][24] = true; // Desert
    geos[2][30] = true; // Cave
    geos[2][6] = true; // Cape
    geos[2][10] = true; // Peninsula
    geos[2][15] = true; // Swamp
    geos[2][19] = true; // Dune
    geos[2][28] = true; // Island
    geos[2][21] = true; // Geyser

    // Earthen
    geos[3][3] = true; // Basin
    geos[3][8] = true; // Plateau
    geos[3][9] = true; // Mesa
    geos[3][18] = true; // Ice Shelf
    geos[3][22] = true; // Glacier
    geos[3][4] = true; // Butte
    geos[3][29] = true; // Canyon
    geos[3][27] = true; // Mountain
    geos[3][34] = true; // Volcano

    // Common
    rarityHolder[0] = 0;
    rarityHolder[1] = 0;
    rarityHolder[10] = 0;
    rarityHolder[11] = 0;
    rarityHolder[20] = 0;
    rarityHolder[21] = 0;
    rarityHolder[30] = 0;
    rarityHolder[31] = 0;

    // Uncommon
    rarityHolder[2] = 1;
    rarityHolder[3] = 1;
    rarityHolder[12] = 1;
    rarityHolder[13] = 1;
    rarityHolder[22] = 1;
    rarityHolder[23] = 1;
    rarityHolder[32] = 1;
    rarityHolder[33] = 1;

    // Rare
    rarityHolder[4] = 2;
    rarityHolder[5] = 2;
    rarityHolder[14] = 2;
    rarityHolder[15] = 2;
    rarityHolder[24] = 2;
    rarityHolder[25] = 2;
    rarityHolder[34] = 2;
    rarityHolder[35] = 2;

    // Epic
    rarityHolder[6] = 3;
    rarityHolder[16] = 3;
    rarityHolder[26] = 3;
    rarityHolder[36] = 3;

    // Legendary
    rarityHolder[7] = 4;
    rarityHolder[17] = 4;
    rarityHolder[27] = 4;
    rarityHolder[37] = 4;

    // Mythic
    rarityHolder[8] = 5;
    rarityHolder[18] = 5;
    rarityHolder[28] = 5;
    rarityHolder[38] = 5;

    // Exotic
    rarityHolder[9] = 6;
    rarityHolder[19] = 6;
    rarityHolder[29] = 6;
    rarityHolder[39] = 6;

    cooldowns = [43200, 43200, 86400, 86400, 129600, 129600, 172800];
    costs = [
      100000000000000000,
      150000000000000000,
      300000000000000000,
      500000000000000000,
      1000000000000000000,
      1250000000000000000,
      2000000000000000000
    ];
  }

  //=======================================
  // External
  //=======================================
  function activate(uint256[] calldata _realmIds)
    external
    nonReentrant
    whenNotPaused
  {
    for (uint256 j = 0; j < _realmIds.length; j++) {
      uint256 realmId = _realmIds[j];

      // Check if reactor is productive
      require(
        STRUCTURE_STAKER.hasStaked(realmId, address(REACTOR), 0),
        "CollectibleProducer: Not productive"
      );

      // Set production
      PRODUCTION.setProduction(realmId);

      emit Activated(realmId);
    }
  }

  function collect(
    uint256[] calldata _realmIds,
    uint256[][] calldata _collectibleIds,
    uint256[][] calldata _quantities
  ) external nonReentrant whenNotPaused {
    for (uint256 h = 0; h < _realmIds.length; h++) {
      uint256 realmId = _realmIds[h];

      // Check ownership
      require(
        REALM.ownerOf(realmId) == msg.sender,
        "CollectibleProducer: You do not own this Realm"
      );

      uint256[] memory collectibleIds = _collectibleIds[h];
      uint256[] memory quantities = _quantities[h];

      // Check if _collectibleIds are below max
      require(
        collectibleIds.length <= maxCollectibles,
        "CollectibleProducer: Above max Collectibles"
      );

      // Check if reactor is productive
      require(
        STRUCTURE_STAKER.hasStaked(realmId, address(REACTOR), 0),
        "CollectibleProducer: Not productive"
      );

      // Check if production is initialized
      require(
        PRODUCTION.isProductive(realmId),
        "CollectibleProducer: You must start production first"
      );

      uint256 startedAt = PRODUCTION.getStartedAt(realmId);

      for (uint256 j = 0; j < collectibleIds.length; j++) {
        uint256 collectibleId = collectibleIds[j];
        uint256 desiredQuantity = quantities[j];

        // Collect
        _collect(realmId, collectibleId, desiredQuantity, startedAt);
      }
    }
  }

  function getSecondsElapsed(uint256 _realmId) external view returns (uint256) {
    uint256 startedAt = PRODUCTION.getStartedAt(_realmId);

    // Return 0 if production hasn't been started
    if (startedAt == 0) return 0;

    return _secondsElapsed(startedAt);
  }

  function getQuantity(uint256 _realmId, uint256 _collectibleId)
    external
    view
    returns (uint256)
  {
    uint256 rarity = _getRarity(_collectibleId);
    uint256 startedAt = PRODUCTION.getStartedAt(_realmId);

    // Return 0 if production hasn't been started
    if (startedAt == 0) return 0;

    uint256 cooldown = cooldowns[rarity];

    return _secondsElapsed(startedAt) / cooldown;
  }

  function secondsTillIncrease(uint256 _realmId, uint256 _collectibleId)
    external
    view
    returns (uint256)
  {
    uint256 rarity = _getRarity(_collectibleId);
    uint256 startedAt = PRODUCTION.getStartedAt(_realmId);

    // Return 0 if production hasn't been started
    if (startedAt == 0) return 0;

    uint256 cooldown = cooldowns[rarity];
    uint256 elapsedTime = _secondsElapsed(startedAt);

    return cooldown - (elapsedTime - ((elapsedTime / cooldown) * cooldown));
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

  function updateCosts(uint256[] calldata _costs) external onlyAdmin {
    costs = _costs;
  }

  function updateCooldowns(uint256[] calldata _cooldowns) external onlyAdmin {
    cooldowns = _cooldowns;
  }

  function updateMaxCollectibles(uint256 _maxCollectibles) external onlyAdmin {
    maxCollectibles = _maxCollectibles;
  }

  function updateMaxSeconds(uint256 _maxSeconds) external onlyAdmin {
    maxSeconds = _maxSeconds;
  }

  //=======================================
  // Internal
  //=======================================

  function _collect(
    uint256 _realmId,
    uint256 _collectibleId,
    uint256 _desiredQuantity,
    uint256 _startedAt
  ) internal {
    // Get rarity
    uint256 rarity = _getRarity(_collectibleId);

    // Get cooldown
    uint256 cooldown = cooldowns[rarity];

    // Get category
    uint256 category = _getCategory(_collectibleId);

    // Store if has Geo Feature
    bool hasGeo = _hasGeo(_realmId, category);

    // Check if trying to collect Exotic
    if (rarity == 6) {
      require(
        _hasExotic(_realmId, category),
        "CollectibleProducer: You cannot produce Exotic Collectible"
      );
    }

    // Require Geo Feature if not Common Rarity
    if (rarity != 0) {
      require(
        hasGeo,
        "CollectibleProducer: You cannot produce this Collectible"
      );
    }

    // Seconds elapsed
    uint256 secondsElapsed = _secondsElapsed(_startedAt);

    // Check over max seconds to collect
    if (secondsElapsed > maxSeconds) {
      secondsElapsed = maxSeconds;
    }

    // Get quantity
    uint256 quantity = secondsElapsed / cooldown;

    // Check if quantity is greater than 0
    require(
      quantity > 0,
      "CollectibleProducer: Max quantity allowed must be above 0"
    );

    // Check if desired quantity is allowed
    require(
      quantity >= _desiredQuantity,
      "CollectibleProducer: Desired quantity is above max quantity allowed"
    );

    // Update production
    PRODUCTION.setProduction(_realmId);

    // Get cost
    uint256 cost = costs[rarity] * _desiredQuantity;

    // Transfer to vault
    TOKEN.safeTransferFrom(msg.sender, VAULT, cost);

    // Mint
    COLLECTIBLE.mintFor(msg.sender, _collectibleId, _desiredQuantity);

    emit Produced(_realmId, _collectibleId, _desiredQuantity, cost);
  }

  function _getCategory(uint256 _collectibleId)
    internal
    pure
    returns (uint256)
  {
    if (_collectibleId < 10) {
      return 0;
    } else if (_collectibleId < 20) {
      return 1;
    } else if (_collectibleId < 30) {
      return 2;
    } else {
      return 3;
    }
  }

  function _secondsElapsed(uint256 _time) internal view returns (uint256) {
    if (block.timestamp <= _time) {
      return 0;
    }

    return (block.timestamp - _time);
  }

  function _getRarity(uint256 _collectibleId) internal view returns (uint256) {
    return rarityHolder[_collectibleId];
  }

  function _hasGeo(uint256 _realmId, uint256 _category)
    internal
    view
    returns (bool)
  {
    (uint256 a, uint256 b, uint256 c) = _realmFeatures(_realmId);

    if (geos[_category][a] || geos[_category][b] || geos[_category][c]) {
      return true;
    }

    return false;
  }

  function _hasExotic(uint256 _realmId, uint256 _category)
    internal
    view
    returns (bool)
  {
    (uint256 a, uint256 b, uint256 c) = _realmFeatures(_realmId);

    if (
      a == exotics[_category] ||
      b == exotics[_category] ||
      c == exotics[_category]
    ) {
      return true;
    }

    return false;
  }

  function _realmFeatures(uint256 _realmId)
    internal
    view
    returns (
      uint256,
      uint256,
      uint256
    )
  {
    return (
      REALM.realmFeatures(_realmId, 0),
      REALM.realmFeatures(_realmId, 1),
      REALM.realmFeatures(_realmId, 2)
    );
  }
}

