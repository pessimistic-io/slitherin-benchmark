// SPDX-License-Identifier: UNLICENSED
import "./Actions.sol";
import "./ILastActionMarkerStorage.sol";
import "./IAdventurerData.sol";
import "./IAdventurerGateway.sol";
import "./TraitConstants.sol";
import "./Anima.sol";
import "./IBatchBurnableStaker.sol";
import "./IRewardsPool.sol";
import "./IManager.sol";
import "./ManagerModifier.sol";
import "./IRealm.sol";
import "./IResource.sol";
import "./ResourceConstants.sol";
import "./Epoch.sol";
import "./Random.sol";
import "./IMonumentHomage.sol";
import "./Monument.sol";
import "./Pausable.sol";
import "./ERC721.sol";

pragma solidity ^0.8.17;

contract MonumentHomage is
  IMonumentHomage,
  ManagerModifier,
  Pausable,
  ReentrancyGuard
{
  using Epoch for uint256;

  // Struct used for unwrapping the rewards received from paying homage
  struct RewardsUnwrapper {
    uint256[] tokenTypes;
    address[] tokenAddresses;
    uint256[] tokenIds;
    uint256[] amounts;
  }

  // Struct used for tracking the structures that need to be burned
  struct StructuresToBurn {
    uint256 totalDestinations;
    uint256 totalStructures;
    uint256[] realmIds;
    uint256[] structureIds;
    uint256[] amounts;
  }

  // Emitted when a successful homage transaction occurs
  event HomageResult(
    uint256 homageId,
    uint256 realmId,
    uint256 structureId,
    address adventurerAddress,
    uint256 adventurerId,
    uint256[] tokenTypes,
    address[] tokenAddresses,
    uint256[] tokenIds,
    uint256[] amounts
  );

  // Monument configuration
  struct MonumentHomageConfig {
    uint64 minimumLevel;
    uint256 animaCost;
    uint64 epochCost;
    uint64 rewardPoolId;
    uint256 animaCapacity;
  }

  //=======================================
  // Constants
  //=======================================

  uint256 private constant EPOCH_DURATION = 1 days;
  uint256 private constant EPOCH_OFFSET = 12 hours;

  //=======================================
  // Immutables
  //=======================================
  Monument public immutable MONUMENT;
  IAdventurerGateway public immutable GATEWAY;
  Anima public immutable ANIMA;
  IBatchBurnableStaker public immutable BATCH_STAKER;
  ILastActionMarkerStorage public immutable ACTION_STORAGE;
  IAdventurerData public immutable ADVENTURER_DATA;
  IRewardsPool public immutable REWARDS_POOL;

  //=======================================
  // References
  //=======================================
  IResource public RESOURCE;

  //=======================================
  // Mappings
  //=======================================
  mapping(uint256 => MonumentHomageConfig) public HOMAGE_CONFIG;

  //=======================================
  // Uints
  //=======================================
  uint256 public nextHomageId;
  uint256 MINIMUM_GAS_PER_HOMAGE;
  uint256 public MAX_HOMAGE_POINTS;

  //=======================================
  // Addresses
  //=======================================
  address public BURN_TARGET;

  //=======================================
  // Constructor
  //=======================================
  // The constructor for the MonumentHomage contract.
  // It initializes the contract with necessary contract addresses for inter-contract interactions,
  // sets the maximum number of homage points an adventurer can have, and defines the minimum gas required for paying homage.
  constructor(
    address _manager,
    address _structureStaker,
    address _actionStorage,
    address _monument,
    address _gateway,
    address _resource,
    address _adventurerData,
    address _anima,
    address _rewardsPool
  ) ManagerModifier(_manager) {
    BATCH_STAKER = IBatchBurnableStaker(_structureStaker);
    ACTION_STORAGE = ILastActionMarkerStorage(_actionStorage);
    MONUMENT = Monument(_monument);
    GATEWAY = IAdventurerGateway(_gateway);
    RESOURCE = IResource(_resource);
    ADVENTURER_DATA = IAdventurerData(_adventurerData);
    ANIMA = Anima(_anima);
    REWARDS_POOL = IRewardsPool(_rewardsPool);
    MAX_HOMAGE_POINTS = 7;
    MINIMUM_GAS_PER_HOMAGE = 300000;
  }

  //=======================================
  // Functions
  //=======================================

  // The payHomage function allows an adventurer to pay homage to a monument.
  // This function checks that the adventurer owns the adventurer token, validates the adventurer's address,
  // checks that the adventurer is allowed to pay homage (based on the last time they paid homage),
  // increases the amount of Anima Capacity in the realm, burns the necessary structures, and burns Anima from the adventurer.
  // The function also emits a HomageResult event for each homage paid and emits rewards for the Adventurer (usually in the form of lootboxes).
  function payHomage(
    HomageRequest[] calldata _requests
  ) external nonReentrant whenNotPaused {
    // Ensure homage is paid directly by an adventurer, not through another contract
    require(
      msg.sender == tx.origin,
      "MonumentHomage: Homage is not allowed through another contract"
    );

    // Prepare a batch of structures to burn
    StructuresToBurn memory structuresToBurn;
    uint256 i;
    for (i = 0; i < _requests.length; i++) {
      HomageRequest calldata request = _requests[i];
      structuresToBurn.totalDestinations += request.destinations.length;
      for (uint256 j = 0; j < request.destinations.length; j++) {
        structuresToBurn.totalStructures += request
          .destinations[j]
          .structureAmount;
      }
    }

    // Allocate memory for storing realms and structures to burn
    structuresToBurn.realmIds = new uint256[](
      structuresToBurn.totalDestinations
    );
    structuresToBurn.structureIds = new uint256[](
      structuresToBurn.totalDestinations
    );
    structuresToBurn.amounts = new uint256[](
      structuresToBurn.totalDestinations
    );

    // Ensure enough gas is available to prevent manipulation of randomness
    require(
      gasleft() > (MINIMUM_GAS_PER_HOMAGE * structuresToBurn.totalStructures),
      "MonumentHomage: Manual gas reduction is not allowed"
    );

    // Start the homage process, prepare intermediate variables
    uint256 currentEpoch = block.timestamp.toEpoch(
      EPOCH_DURATION,
      EPOCH_OFFSET
    );
    uint256 totalAnima;
    uint256 destinationIterator;
    uint256 destinationCost;
    uint256 homageIndex = nextHomageId;
    uint256 randomBase = Random.startRandomBase(
      uint256(uint160(address(this))),
      nextHomageId
    );
    // Process each homage request
    for (i = 0; i < _requests.length; i++) {
      HomageRequest calldata request = _requests[i];
      address owner = ERC721(request.adventurerAddress).ownerOf(
        request.adventurerId
      );
      // Ensure the homage is paid by the adventurer owner and that the adventurer is eligible to pay homage
      require(owner == msg.sender, "MonumentHomage: You do not own Adventurer");
      GATEWAY.checkAddress(request.adventurerAddress, request.proofs);

      // Calculate the number of epochs since the last homage
      uint256 epochsSinceLastHomage = _getHomagePoints(
        currentEpoch,
        request.adventurerAddress,
        request.adventurerId
      );

      // Process each destination for the homage
      for (uint256 j = 0; j < request.destinations.length; j++) {
        HomageDestination calldata destination = request.destinations[j];
        MonumentHomageConfig storage homageConfig = HOMAGE_CONFIG[
          destination.structureId
        ];
        require(
          homageConfig.animaCost > 0,
          "MonumentHomage: Structure not configured"
        );

        destinationCost = destination.structureAmount * homageConfig.epochCost;
        // Ensure the adventurer has enough homage points (epochs since last homage)
        require(
          epochsSinceLastHomage >= destinationCost,
          "MonumentHomage: Adventurer is already paid homage this epoch"
        );

        // Ensure the adventurer's level is high enough to pay homage
        require(
          ADVENTURER_DATA.aov(
            request.adventurerAddress,
            request.adventurerId,
            traits.ADVENTURER_TRAIT_LEVEL
          ) >= homageConfig.minimumLevel,
          "MonumentHomage: Adventurer can't pay homage to this monument, transcendence level too low"
        );

        // Subtract this destination's cost from remaining homage points
        epochsSinceLastHomage -= destinationCost;

        // Add to the total anima cost for the homage
        totalAnima += homageConfig.animaCost * destination.structureAmount;

        // Add the anima capacity to the realm
        RESOURCE.add(
          destination.realmId,
          resources.ANIMA_CAPACITY,
          homageConfig.animaCapacity * destination.structureAmount
        );

        // Save the details of the structures to be burnt later
        structuresToBurn.realmIds[destinationIterator] = destination.realmId;
        structuresToBurn.structureIds[destinationIterator] = destination
          .structureId;
        structuresToBurn.amounts[destinationIterator] = destination
          .structureAmount;

        // Increment destinationIterator
        destinationIterator++;

        // Dispense rewards for each structure in the homage
        for (uint256 k = 0; k < destination.structureAmount; k++) {
          // Dispense rewards
          DispensedRewards memory dispensedRewards = REWARDS_POOL
            .dispenseRewards(homageConfig.rewardPoolId, randomBase, msg.sender);

          // Update random base for the next reward
          randomBase = dispensedRewards.nextRandomBase;
          // Emit event for the dispensed rewards
          _emitRewards(
            dispensedRewards,
            homageIndex++,
            destination.realmId,
            destination.structureId,
            request.adventurerAddress,
            request.adventurerId
          );
        }
      }

      // Mark the last pay homage time for the adventurer
      ACTION_STORAGE.setActionMarker(
        request.adventurerAddress,
        request.adventurerId,
        ACTION_ADVENTURER_HOMAGE,
        block.timestamp
      );
    }

    nextHomageId = homageIndex;

    // Burn the structures in the realms as part of the homage
    BATCH_STAKER.burnBatchFor(
      address(MONUMENT),
      structuresToBurn.realmIds,
      structuresToBurn.structureIds,
      structuresToBurn.amounts
    );

    // Burn the total anima cost from the adventurer
    ANIMA.burnFrom(msg.sender, totalAnima);
  }

  // The _emitRewards function emits the HomageResult event with the rewards dispensed to the adventurer.
  // It creates an array of the dispensed rewards and includes them in the HomageResult event.
  function _emitRewards(
    DispensedRewards memory dispensedRewards,
    uint256 homageIndex,
    uint256 realmId,
    uint256 structureId,
    address advAddress,
    uint256 advId
  ) internal {
    RewardsUnwrapper memory emittedRewards;
    emittedRewards.tokenTypes = new uint256[](dispensedRewards.rewards.length);
    emittedRewards.tokenAddresses = new address[](
      dispensedRewards.rewards.length
    );
    emittedRewards.tokenIds = new uint256[](dispensedRewards.rewards.length);
    emittedRewards.amounts = new uint256[](dispensedRewards.rewards.length);

    for (uint i = 0; i < emittedRewards.tokenTypes.length; i++) {
      DispensedReward memory reward = dispensedRewards.rewards[i];
      emittedRewards.tokenTypes[i] = (uint256)(reward.tokenType);
      emittedRewards.tokenAddresses[i] = reward.token;
      emittedRewards.tokenIds[i] = reward.tokenId;
      emittedRewards.amounts[i] = reward.amount;
    }

    emit HomageResult(
      homageIndex,
      realmId,
      structureId,
      advAddress,
      advId,
      emittedRewards.tokenTypes,
      emittedRewards.tokenAddresses,
      emittedRewards.tokenIds,
      emittedRewards.amounts
    );
  }

  //=======================================
  // Views
  //=======================================

  // The getEligibleStructureAmounts function returns the amounts of each structure that the Monument contract is allowed to burn.
  // It fetches the staker balance for each structure for the Monument contract.
  function getEligibleStructureAmounts(
    uint256[] calldata _realmIds,
    uint256[] calldata _tokenIds
  ) external view returns (uint256[] memory) {
    uint256[] memory result = new uint256[](_realmIds.length);
    for (uint256 i = 0; i < _realmIds.length; i++) {
      result[i] = BATCH_STAKER.stakerBalance(
        _realmIds[i],
        address(MONUMENT),
        _tokenIds[i]
      );
    }
    return result;
  }

  // The getAdventurerHomagePoints function returns the number of homage points each adventurer has.
  // It calculates the number of epochs since each adventurer's last action and returns the smaller of that number and the maximum number of homage points.
  function getAdventurerHomagePoints(
    address[] calldata _addresses,
    uint256[] calldata _adventurerIds
  ) external view override returns (uint256[] memory result) {
    uint256 currentEpoch = block.timestamp.toEpoch(
      EPOCH_DURATION,
      EPOCH_OFFSET
    );

    result = new uint256[](_addresses.length);
    for (uint256 i = 0; i < _addresses.length; i++) {
      result[i] = _getHomagePoints(
        currentEpoch,
        _addresses[i],
        _adventurerIds[i]
      );
    }
  }

  function _getHomagePoints(
    uint256 _epoch,
    address _address,
    uint256 _tokenId
  ) internal view returns (uint256) {
    uint256 epochsSinceLastAction = _epoch -
      ACTION_STORAGE
        .getActionMarker(_address, _tokenId, ACTION_ADVENTURER_HOMAGE)
        .toEpoch(EPOCH_DURATION, EPOCH_OFFSET);
    return
      epochsSinceLastAction > MAX_HOMAGE_POINTS
        ? MAX_HOMAGE_POINTS
        : epochsSinceLastAction;
  }

  //=======================================
  // Admin
  //=======================================

  // The configureStructures function allows the admin to configure the homage costs and rewards for each structure.
  // It sets the minimum level, Anima cost, epoch cost, reward pool ID, and Anima capacity for each structure.
  function configureStructures(
    uint256[] calldata _tokenIds,
    uint64[] calldata _minimumLevels,
    uint256[] calldata _animaCosts,
    uint64[] calldata _epochCosts,
    uint64[] calldata _tokenIdRewardPoolIds,
    uint256[] calldata _animaCapacity
  ) public onlyAdmin {
    require(_tokenIds.length == _minimumLevels.length);
    require(_tokenIds.length == _epochCosts.length);
    require(_tokenIds.length == _animaCosts.length);
    require(_tokenIds.length == _tokenIdRewardPoolIds.length);

    for (uint256 i = 0; i < _tokenIds.length; i++) {
      HOMAGE_CONFIG[_tokenIds[i]] = MonumentHomageConfig(
        _minimumLevels[i],
        _animaCosts[i],
        _epochCosts[i],
        _tokenIdRewardPoolIds[i],
        _animaCapacity[i]
      );
    }
  }

  // Set minimum gas required (per lootbox)
  function updateMinimumGas(uint256 _minimumGas) external onlyAdmin {
    MINIMUM_GAS_PER_HOMAGE = _minimumGas;
  }

  // Set maximum number of epochs that the Adventurer can stack
  function updateMaxHomagePoints(uint256 _maxHomage) external onlyAdmin {
    MAX_HOMAGE_POINTS = _maxHomage;
  }

  // Set maximum number of epochs that the Adventurer can stack
  function updateResourceStorage(address _resource) external onlyAdmin {
    RESOURCE = IResource(_resource);
  }
}

