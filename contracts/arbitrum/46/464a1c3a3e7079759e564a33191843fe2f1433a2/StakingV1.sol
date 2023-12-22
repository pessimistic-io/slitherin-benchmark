// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./IERC721Receiver.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";

interface IRealm {
  function ownerOf(uint256 _realmId) external view returns (address owner);

  function isApprovedForAll(address owner, address operator)
    external
    returns (bool);

  function safeTransferFrom(
    address from,
    address to,
    uint256 tokenId
  ) external;
}

interface IData {
  function addGoldSupply(uint256 _realmId, uint256 _gold) external;

  function data(uint256 _realmId, uint256 _type) external returns (uint256);

  function gold(uint256 _realmId) external returns (uint256);

  function add(
    uint256 _realmId,
    uint256 _type,
    uint256 _amount
  ) external;

  function remove(
    uint256 _realmId,
    uint256 _type,
    uint256 _amount
  ) external;
}

interface IStructure {
  function add(
    uint256 _realmId,
    uint256 _type,
    uint256 _amount
  ) external;

  function data(uint256 _realmId, uint256 _type) external returns (uint256);
}

interface IResource {
  function add(
    uint256 _realmId,
    uint256 _resourceId,
    uint256 _amount
  ) external;
}

interface IManager {
  function isAdmin(address addr) external view returns (bool);
}

interface IRand {
  function retrieve(uint256 salt) external view returns (uint256);
}

contract StakingV1 is IERC721Receiver, ReentrancyGuard, Pausable {
  //=======================================
  // Immutables
  //=======================================
  IRealm public immutable REALM;
  IData public immutable DATA;
  IStructure public immutable STRUCTURE;
  IResource public immutable RESOURCE;
  IManager public immutable MANAGER;

  //=======================================
  // Constants
  //=======================================
  uint256 public constant TIER_1 = 7;
  uint256 public constant TIER_2 = 3;
  uint256 public constant MAX_COLLECT = 5;

  //=======================================
  // Structs
  //=======================================
  struct Staker {
    address staker;
    uint256 resourceId;
    uint256 stakedAt;
  }

  //=======================================
  // Mappings
  //=======================================
  mapping(uint256 => Staker) public stakers;
  mapping(uint256 => uint256) public collected;

  //=======================================
  // Arrays
  //=======================================
  uint256[] public bonusProbability = [40, 85, 95, 100];

  uint256[] public resourceProbability = [
    40,
    52,
    62,
    72,
    77,
    82,
    87,
    91,
    94,
    97,
    100
  ];
  uint256[] public cultureIds = [0, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17];
  uint256[] public techIds = [0, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27];
  uint256[] public foodIds = [0, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37];

  //=======================================
  // Randomizer
  //=======================================
  IRand public randomizer;

  //=======================================
  // EVENTS
  //=======================================
  event Staked(uint256 realmId, uint256 resourceId);
  event Unstaked(uint256 realmId);
  event Build(uint256 realmId);

  event Collected(uint256 realmId);
  event CollectedWithResourceId(uint256 realmId, uint256 resourceId);

  event DataAdded(
    uint256 realmId,
    uint256 resourceId,
    uint256 resource,
    uint256 structure,
    uint256 tier,
    uint256 bonus,
    uint256 multipler,
    uint256 amount
  );

  event ResourceChanged(uint256 realmId, uint256 resourceId);

  //=======================================
  // MODIFIER
  //=======================================
  modifier onlyStaker(uint256 _realmId) {
    // Check that sender is staker
    _onlyStaker(_realmId);
    _;
  }

  modifier onlyAdmin() {
    // Check if admin
    require(MANAGER.isAdmin(msg.sender), "Manager: Not an Admin");
    _;
  }

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _realm,
    address _data,
    address _structure,
    address _resource,
    address _manager,
    address _rand
  ) {
    REALM = IRealm(_realm);
    DATA = IData(_data);
    STRUCTURE = IStructure(_structure);
    RESOURCE = IResource(_resource);
    MANAGER = IManager(_manager);

    randomizer = IRand(_rand);
  }

  //=======================================
  // External
  //=======================================
  function stake(uint256 _realmId, uint256 _resourceId)
    external
    nonReentrant
    whenNotPaused
  {
    // Create staker
    Staker storage staker = stakers[_realmId];
    staker.staker = msg.sender;
    staker.resourceId = _resourceId;
    staker.stakedAt = block.timestamp;

    // Add staker to staked mapping
    stakers[_realmId] = staker;

    // Initialize collected
    collected[_realmId] = block.timestamp;

    // Transfer Realm to contract
    REALM.safeTransferFrom(msg.sender, address(this), _realmId);

    emit Staked(_realmId, _resourceId);
  }

  function unstake(uint256 _realmId)
    external
    nonReentrant
    onlyStaker(_realmId)
  {
    Staker storage staker = stakers[_realmId];

    // Reset staker
    staker.staker = address(0);
    staker.resourceId = 0;
    staker.stakedAt = 0;

    // Transfer Realm back to owner
    REALM.safeTransferFrom(address(this), msg.sender, _realmId);

    emit Unstaked(_realmId);
  }

  function unstakeAndBuild(uint256 _realmId)
    external
    nonReentrant
    whenNotPaused
    onlyStaker(_realmId)
  {
    Staker storage staker = stakers[_realmId];

    // Get days elapsed since last collection
    uint256 collectedDaysElapsed = _collectedDaysElapsed(_realmId);

    // Check if days elapsed are greater than 0
    if (collectedDaysElapsed > 0) {
      // Collect
      _collectData(_realmId, collectedDaysElapsed, staker);
    }

    // Build
    _build(_realmId);

    // Reset staker
    staker.staker = address(0);
    staker.resourceId = 0;
    staker.stakedAt = 0;

    // Transfer Realm back to owner
    REALM.safeTransferFrom(address(this), msg.sender, _realmId);

    emit Unstaked(_realmId);
  }

  function collect(uint256 _realmId)
    external
    nonReentrant
    whenNotPaused
    onlyStaker(_realmId)
  {
    // Collect
    _collect(_realmId);

    emit Collected(_realmId);
  }

  function collect(uint256 _realmId, uint256 _resourceId)
    external
    nonReentrant
    whenNotPaused
    onlyStaker(_realmId)
  {
    // Collect
    _collect(_realmId);

    // Update staker resourceId
    stakers[_realmId].resourceId = _resourceId;

    emit CollectedWithResourceId(_realmId, _resourceId);
  }

  function changeResource(uint256 _realmId, uint256 _resourceId)
    external
    nonReentrant
    whenNotPaused
    onlyStaker(_realmId)
  {
    // Update collected timestamp
    collected[_realmId] = block.timestamp;

    // Update resourceId on staker
    stakers[_realmId].resourceId = _resourceId;

    emit ResourceChanged(_realmId, _resourceId);
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

  function setRandomizer(address _addr) external onlyAdmin {
    randomizer = IRand(_addr);
  }

  //=======================================
  // ERC721
  //=======================================

  function onERC721Received(
    address, // _operator,
    address, //_from,
    uint256, // _tokenId,
    bytes calldata //_data
  ) external pure override returns (bytes4) {
    return IERC721Receiver.onERC721Received.selector;
  }

  //=======================================
  // Internal
  //=======================================
  function _collect(uint256 _realmId) internal {
    Staker memory staker = stakers[_realmId];

    // Get days elapsed since last collection
    uint256 collectedDaysElapsed = _collectedDaysElapsed(_realmId);

    // Check that days elapsed is greater than 0
    require(collectedDaysElapsed > 0, "Staking: Nothing to collect");

    // collect
    _collectData(_realmId, collectedDaysElapsed, staker);

    // Update collected timestamp
    collected[_realmId] = block.timestamp;
  }

  function _collectData(
    uint256 _realmId,
    uint256 _daysMultiplier,
    Staker memory staker
  ) internal {
    // Check that days multiplier doesn't exceed max collect
    if (_daysMultiplier > 5) {
      _daysMultiplier = MAX_COLLECT;
    }

    // Get stake multipliers
    (uint256 tier1, uint256 tier2) = _builtMultipliers(_realmId);

    // Get random amount
    uint256 amount = _rarity(staker.stakedAt, bonusProbability) + 1;

    if (staker.resourceId == 0) {
      // Add gold
      _addData(
        _realmId,
        0,
        DATA.gold(_realmId),
        STRUCTURE.data(_realmId, 0),
        amount,
        tier1,
        _daysMultiplier
      );
    } else if (staker.resourceId == 1) {
      // Add food
      _addData(
        _realmId,
        1,
        0,
        STRUCTURE.data(_realmId, 1),
        amount,
        tier2,
        _daysMultiplier
      );
    } else if (staker.resourceId == 3) {
      // Add Culture
      _addData(
        _realmId,
        3,
        0,
        STRUCTURE.data(_realmId, 2),
        amount,
        tier2,
        _daysMultiplier
      );
    } else if (staker.resourceId == 5) {
      // Add Technology
      _addData(
        _realmId,
        5,
        0,
        STRUCTURE.data(_realmId, 3),
        amount,
        tier2,
        _daysMultiplier
      );
    }
  }

  function _addData(
    uint256 _realmId,
    uint256 _resourceId,
    uint256 _resource,
    uint256 _structure,
    uint256 _amount,
    uint256 _tier,
    uint256 _multiplier
  ) internal {
    // Check that there is something to add
    if (_tier == 0 && _structure == 0) return;

    // Calculate resource amount
    uint256 amount = (_resource + _structure + _tier + _amount) * _multiplier;

    // Add data
    DATA.add(_realmId, _resourceId, amount);

    // Add collectibles
    _addCollectibles(_realmId, _resourceId);

    emit DataAdded(
      _realmId,
      _resourceId,
      _resource,
      _structure,
      _tier,
      _amount,
      _multiplier,
      amount
    );
  }

  function _addCollectibles(uint256 _realmId, uint256 _resourceId) internal {
    // If resource is Gold then return
    if (_resourceId == 0) return;

    uint256 id;

    if (_resourceId == 1) {
      id = foodIds[_rarity(_resourceId, resourceProbability)];
    } else if (_resourceId == 3) {
      id = cultureIds[_rarity(_resourceId, resourceProbability)];
    } else if (_resourceId == 5) {
      id = techIds[_rarity(_resourceId, resourceProbability)];
    }

    // Resturn if resource ID is 0
    if (id == 0) return;

    // Add resources
    RESOURCE.add(_realmId, id, 1);
  }

  function _build(uint256 _realmId) internal {
    // Get built multipliers for both tiers
    (uint256 tier1, uint256 tier2) = _builtMultipliers(_realmId);

    // City
    STRUCTURE.add(_realmId, 0, tier1);
    // Farm
    STRUCTURE.add(_realmId, 1, tier2);
    // Aquarium
    STRUCTURE.add(_realmId, 2, tier2);
    // Research Lab
    STRUCTURE.add(_realmId, 3, tier2);

    // Add to Gold supply
    DATA.addGoldSupply(_realmId, tier1);

    emit Build(_realmId);
  }

  function _builtMultipliers(uint256 _realmId)
    internal
    view
    returns (uint256, uint256)
  {
    uint256 multiplier = _stakedDaysElapsed(_realmId);

    return (multiplier / TIER_1, multiplier / TIER_2);
  }

  function _collectedDaysElapsed(uint256 _realmId)
    internal
    view
    returns (uint256)
  {
    return _daysElapsed(collected[_realmId]);
  }

  function _stakedDaysElapsed(uint256 _realmId)
    internal
    view
    returns (uint256)
  {
    return _daysElapsed(stakers[_realmId].stakedAt);
  }

  function _daysElapsed(uint256 _time) internal view returns (uint256) {
    if (block.timestamp <= _time) {
      return 0;
    }

    return (block.timestamp - _time) / (24 * 60 * 60);
  }

  function _rarity(uint256 _salt, uint256[] memory probability)
    internal
    view
    returns (uint256)
  {
    uint256 rand = uint256(
      keccak256(
        abi.encodePacked(
          block.number,
          block.timestamp,
          randomizer.retrieve(_salt)
        )
      )
    ) % 100;

    uint256 j = 0;
    for (; j < probability.length; j++) {
      if (rand <= probability[j]) {
        break;
      }
    }
    return j;
  }

  function _onlyStaker(uint256 _realmId) internal view {
    require(
      stakers[_realmId].staker == msg.sender,
      "Staking: You did not stake this realm"
    );
  }
}

