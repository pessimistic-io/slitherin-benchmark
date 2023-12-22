//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./ERC721HolderUpgradeable.sol";
import "./IERC721.sol";

import "./UtilitiesV2Upgradeable.sol";
import "./IRandomizer.sol";
import "./ISmolTreasures.sol";
import "./ISmolRacingTrophies.sol";

abstract contract SmolRacingState is
    Initializable,
    UtilitiesV2Upgradeable,
    ERC721HolderUpgradeable
{
    event SmolStaked(
        address indexed _owner,
        address indexed _smolAddress,
        uint256 indexed _tokenId,
        uint64 _stakeTime
    );
    event StartRacing(
        address indexed _owner,
        address indexed _vehicleAddress,
        uint256 indexed _tokenId,
        uint64 _stakeTime,
        uint8 _totalRaces,
        uint64[4] _driverIds,
        uint256 _requestId
    );
    event RestartRacing(
        address indexed _owner,
        address indexed _vehicleAddress,
        uint256 indexed _tokenId,
        uint64 _stakeTime,
        uint8 _totalRaces,
        uint64[4] _driverIds,
        uint256 _requestId
    );
    event StopRacing(
        address indexed _owner,
        address indexed _vehicleAddress,
        uint256 indexed _tokenId,
        uint64 _stakeTime,
        uint8 _totalRaces
    );
    event SmolUnstaked(
        address indexed _owner,
        address indexed _smolAddress,
        uint256 indexed _tokenId
    );
    event RewardClaimed(
        address indexed _owner,
        address indexed _vehicleAddress,
        uint256 indexed _tokenId,
        uint256 _claimedRewardId,
        uint256 _amount
    );
    event NoRewardEarned(
        address indexed _owner,
        address indexed _vehicleAddress,
        uint256 indexed _tokenId
    );

    ISmolRacingTrophies public racingTrophies;
    ISmolTreasures public treasures;

    IRandomizer public randomizer;

    IERC721 public smolBrains;
    IERC721 public smolBodies;
    IERC721 public smolCars;
    IERC721 public swolercycles;

    // collection address -> user address -> tokens staked for collection
    // collection address can be either SmolCars or Swolercycles
    // token staked is the tokenId of the SmolCar or Swolercycle
    // data for staked smols is in the following mapping
    mapping(address => mapping(address => EnumerableSetUpgradeable.UintSet))
        internal userToVehiclesStaked;

    // collection address => tokenId => Vehicle
    // collection address can be either SmolCars or Swolercycles
    // tokenId is the id of the SmolCar or Swolercycle
    // Vehicle contains ids of who is inside the vehicle and other racing info
    // It is assumed that SmolCars have SmolBrains in them, and Swolercycles have SmolBodies in them
    mapping(address => mapping(uint256 => Vehicle))
        internal vehicleIdToVehicleInfo;

    // collection address => tokenId => Vehicle
    // collection address can be either SmolCars or Swolercycles
    // tokenId is the id of the SmolCar or Swolercycle
    // RacingInfo contains metadata for calculating rewards and determining unstake-ability
    mapping(address => mapping(uint256 => RacingInfo))
        internal vehicleIdToRacingInfo;

    // collection address -> tokenId -> info
    // collection address can be either SmolCars or Swolercycles
    // tokenId is the id of the SmolCar or Swolercycle
    mapping(address => mapping(uint256 => uint256)) public tokenIdToRequestId;

    mapping(address => mapping(uint256 => uint256))
        public tokenIdToStakeStartTime;
    mapping(address => mapping(uint256 => uint256))
        public tokenIdToRewardsClaimed;
    mapping(address => mapping(uint256 => uint256))
        public tokenIdToRewardsInProgress;

    mapping(uint256 => uint32) public smolTreasureIdToOddsBoost;

    uint32 public constant ODDS_DENOMINATOR = 100_000_000;
    uint32 public maxOddsBoostAllowed;
    uint32 public additionalSmolBrainBoost;
    uint32 public additionalSmolBodyBoost;

    uint256[] public rewardOptions;
    // Odds out of 100,000,000
    // treasureTokenId -> Odds of getting reward
    mapping(uint256 => uint32) public rewardIdToOdds;

    uint256 public timeForReward;

    uint256 public endEmissionTime;

    function __SmolRacingState_init() internal initializer {
        UtilitiesV2Upgradeable.__Utilities_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();

        timeForReward = 1 days;

        // Odds are calculated out of 100,000,000 (100 million). This is to obtain the 6 digit precision needed for treasure boost amounts
        // .667% increase per smol after the first one (since the max in a car is 4, caps at 2.001%)
        additionalSmolBrainBoost = 667_000;
        // Having a second body on a cycle increases odds by 1%
        additionalSmolBodyBoost = 1_000_000; // 1 million out of 100 million is 1%
        maxOddsBoostAllowed = 2_500_000; // 2.5% max boost

        uint256 moonrockId = 1;
        uint256 stardustId = 2;
        uint256 cometShardId = 3;
        uint256 lunarGoldId = 4;

        smolTreasureIdToOddsBoost[moonrockId] = 2;     // 0.000002% increase per moonrock
        smolTreasureIdToOddsBoost[stardustId] = 5;     // 0.000005% increase per stardust
        smolTreasureIdToOddsBoost[cometShardId] = 12;  // 0.000012% increase per comet shard
        smolTreasureIdToOddsBoost[lunarGoldId] = 27;   // 0.000027% increase per lunar gold

        // rewards setup after initialization
    }

    struct BoostItem {
        uint64 treasureId;
        uint64 quantity;
    }

    struct BoostItemOdds {
        uint64 quantityNeededForBoost;
        uint32 oddsBoostPerQuantity;
    }

    struct SmolCar {
        uint64[4] driverIds;
        uint64 carId;
        uint8 numRaces;
        uint8 numDrivers;
        uint64[] boostTreasureIds;
        uint32[] boostTreasureQuantities;
    }

    struct Swolercycle {
        uint64[2] driverIds;
        uint64 cycleId;
        uint8 numRaces;
        uint8 numDrivers;
        uint64[] boostTreasureIds;
        uint32[] boostTreasureQuantities;
    }

    struct Vehicle {
        uint64[4] driverIds;
        uint64 vehicleId;
        uint8 numRaces;
        uint8 numDrivers;
        uint64[] boostTreasureIds;
        uint32[] boostTreasureQuantities;
    }

    struct RacingInfo {
        uint64 racingStartTime;
        uint8 totalRaces;
        uint8 racesCompleted;
        uint64 lastClaimed;
        uint32 boostedOdds; // out of 100,000,000 (6 digit precision)
    }
}
