// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./console.sol";

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20.sol";
import "./IERC721.sol";

contract Race2Uranus is Initializable, UUPSUpgradeable, OwnableUpgradeable {
  /**
  ______                _____  _   _                           
  | ___ \              / __  \| | | |                          
  | |_/ /__ _  ___ ___ `' / /'| | | |_ __ __ _ _ __  _   _ ___ 
  |    // _` |/ __/ _ \  / /  | | | | '__/ _` | '_ \| | | / __|
  | |\ \ (_| | (_|  __/./ /___| |_| | | | (_| | | | | |_| \__ \
  \_| \_\__,_|\___\___|\_____/ \___/|_|  \__,_|_| |_|\__,_|___/
                                                             

   */

  event RaceCreated(uint256 indexed raceId);

  event RaceEntered(uint256 indexed raceId, uint8 rocketId, address rocketeer, address nft, uint256 nftId);

  event StakedOnRocket(uint256 indexed raceId, uint8 rocketId, address staker, uint256 amount);

  event BoostApplied(uint256 indexed raceId, uint8 rocketId, address booster);

  event RaceStarted(uint256 indexed raceId, uint256 blastOffTimestamp, uint256 revealBlockNumber);

  event RaceFinished(uint256 indexed raceId, uint8 winningRocketId, address nft, uint256 nftId, address rocketeer);

  event StakeRewardClaimed(uint256 indexed raceId, address indexed staker, uint256 amount);

  event RocketeerRewardClaimed(uint256 indexed raceId, address indexed rocketeer, uint256 amount);

  struct TimeParams {
    uint32[] blastOffTimes;
    uint8 revealDelayMinutes;
    uint32 blockTimeMillis;
  }

  struct RaceConfig {
    uint8 maxRockets;
    uint256 minStakeAmount;
    uint256 maxStakeAmount;
    uint256 revealBounty;
    uint256 boostPrice;
    uint8 boostAmount;
    uint8 rocketsSharePercent;
    uint8 winningRocketSharePercent;
    uint8 devFeePercent;
    address[] whitelistedNfts;
  }

  struct Race {
    uint256 id;
    RaceConfig configSnapshot;
    bool started;
    bool finished;
    uint256 blastOffTimestamp;
    uint256 revealBlock;
    Rocket[] rockets;
    uint256 rewardPool;
    uint8 winner;
    uint256 rewardPerShare;
    uint256 winningRocketShare;
    uint256 otherRocketsShare;
  }

  struct Rocket {
    uint8 id;
    address rocketeer;
    address nft;
    uint256 nftId;
    uint256 totalStake;
    uint8 totalBoosts;
  }

  IERC20 public magic;
  address public beneficiary;

  bool public autoCreateNextRace;
  uint8 public maxBoostsPerRocket;

  TimeParams timeParams;

  RaceConfig raceConfig;
  Race[] races;
  uint256[] activeRaceIds;
  // raceId => rocketId => user => stake
  mapping(uint256 => mapping(uint8 => mapping(address => uint256))) userStakeForRocket;
  // user => raceId[]
  mapping(address => uint256[]) claimableUserRaceIds;
  // raceId => user[]
  mapping(uint256 => address[]) usersForRaceId;
  // raceId => user => participatedInRace
  mapping(uint256 => mapping(address => bool)) userForRaceId;

  function initialize(
    address _magicAddr,
    address[] calldata _whitelistedNfts,
    address _beneficiary
  ) public initializer {
    __Ownable_init();
    __UUPSUpgradeable_init();

    magic = IERC20(_magicAddr);
    beneficiary = _beneficiary;
    autoCreateNextRace = true;
    maxBoostsPerRocket = 255;

    timeParams.blastOffTimes = [
      0,
      1 hours,
      2 hours,
      3 hours,
      4 hours,
      5 hours,
      6 hours,
      7 hours,
      8 hours,
      9 hours,
      10 hours,
      11 hours,
      12 hours,
      13 hours,
      14 hours,
      15 hours,
      16 hours,
      17 hours,
      18 hours,
      19 hours,
      20 hours,
      21 hours,
      22 hours,
      23 hours
    ];
    timeParams.revealDelayMinutes = 90;
    timeParams.blockTimeMillis = 15000;

    raceConfig = RaceConfig(
      5, // uint8 maxRockets;
      1 ether, // uint256 minStakeAmount;
      1000 ether, // uint256 maxStakeAmount;
      3 ether, // uint256 revealBounty;
      2 ether, // uint256 boostPrice;
      3, // uint8 boostAmount;
      10, // uint8 rocketsSharePercent;
      50, // uint8 winningRocketSharePercent;
      3, // uint8 devFeePercent;
      _whitelistedNfts // address[] whitelistedNfts;
    );
  }

  function _authorizeUpgrade(address) internal override onlyOwner {}

  function setBeneficiary(address _beneficiary) external onlyOwner {
    beneficiary = _beneficiary;
  }

  function setAutoCreateNextRace(bool _autoCreateNextRace) external onlyOwner {
    autoCreateNextRace = _autoCreateNextRace;
  }

  function setRaceConfig(RaceConfig calldata _raceConfig) external onlyOwner {
    require(
      _raceConfig.maxRockets * _raceConfig.minStakeAmount >= _raceConfig.revealBounty,
      'Reveal bounty must be lower than minimum possible reward pool size'
    );
    raceConfig = _raceConfig;
  }

  function getRaceConfig() external view returns (RaceConfig memory) {
    return raceConfig;
  }

  function setTimeParams(TimeParams memory _timeParams) external onlyOwner {
    for (uint32 i = 0; i < _timeParams.blastOffTimes.length; i++) {
      require(uint256(_timeParams.blastOffTimes[i]) < 1 days, 'All blast off times must be within 1 day period');
    }
    timeParams = _timeParams;
  }

  function getTimeParams() external view returns (TimeParams memory) {
    return timeParams;
  }

  function getWhitelistedNfts() public view returns (address[] memory) {
    return raceConfig.whitelistedNfts;
  }

  function getActiveRaceIds() public view returns (uint256[] memory) {
    return activeRaceIds;
  }

  function createRace() external onlyOwner {
    _createRace();
  }

  function _createRace() internal {
    Race storage newRace = races.push();
    newRace.configSnapshot = raceConfig;
    uint256 raceId = races.length - 1;
    newRace.id = raceId;
    activeRaceIds.push(raceId);

    emit RaceCreated(raceId);
  }

  function enterRace(
    uint256 raceId,
    address nft,
    uint256 nftId,
    uint256 amount
  ) public {
    Race storage race = races[raceId];
    require(!race.finished, 'Race already finished');
    require(!race.started, 'Race already started');
    require(race.configSnapshot.maxRockets > race.rockets.length, 'Max rocket limit reached');
    require(_arrayHasAddress(race.configSnapshot.whitelistedNfts, nft), 'You cannot use this NFT to enter the race');
    require(!_rocketsHaveNft(race.rockets, nft, nftId), 'This NFT has already been used to enter this race');
    require(_hasNft(msg.sender, nft, nftId), 'You do not own this nft');

    race.rockets.push();
    uint8 rocketId = uint8(race.rockets.length - 1);
    race.rockets[rocketId].id = rocketId;
    race.rockets[rocketId].rocketeer = msg.sender;
    race.rockets[rocketId].nft = nft;
    race.rockets[rocketId].nftId = nftId;

    stakeOnRocket(raceId, rocketId, amount);

    if (race.configSnapshot.maxRockets == race.rockets.length) {
      startRace(raceId);
    }

    emit RaceEntered(raceId, rocketId, msg.sender, nft, nftId);
  }

  function _hasNft(
    address _owner,
    address _nft,
    uint256 _nftId
  ) internal view returns (bool) {
    return IERC721(_nft).ownerOf(_nftId) == _owner;
  }

  function getRaceCount() public view returns (uint256) {
    return races.length;
  }

  function getRace(uint256 raceId) public view returns (Race memory) {
    return races[raceId];
  }

  function getRocketsForRace(uint256 raceId) external view returns (Rocket[] memory) {
    return races[raceId].rockets;
  }

  function getRocketForRace(uint256 raceId, uint8 rocketId) external view returns (Rocket memory) {
    return races[raceId].rockets[rocketId];
  }

  function _arrayHasAddress(address[] storage list, address addr) internal view returns (bool) {
    bool hasAddress = false;

    for (uint256 i = 0; i < list.length; i++) {
      if (addr == list[i]) {
        hasAddress = true;
        break;
      }
    }

    return hasAddress;
  }

  function _arrayHasId(uint256[] storage list, uint256 id) internal view returns (bool) {
    bool hasId = false;

    for (uint256 i = 0; i < list.length; i++) {
      if (id == list[i]) {
        hasId = true;
        break;
      }
    }

    return hasId;
  }

  function _rocketsHaveNft(
    Rocket[] storage rockets,
    address nft,
    uint256 nftId
  ) internal view returns (bool) {
    bool hasNft = false;

    for (uint256 i = 0; i < rockets.length; i++) {
      if (rockets[i].nft == nft && rockets[i].nftId == nftId) {
        hasNft = true;
        break;
      }
    }

    return hasNft;
  }

  function stakeOnRocket(
    uint256 raceId,
    uint8 rocketId,
    uint256 amount
  ) public {
    Race storage race = races[raceId];
    Rocket storage rocket = race.rockets[rocketId];
    require(!race.finished, 'Race already finished');
    if (race.revealBlock > 0) {
      require(block.number < race.revealBlock, 'Reveal block has already been mined');
    }
    require(amount >= race.configSnapshot.minStakeAmount, 'Stake amount too low');
    require(amount <= race.configSnapshot.maxStakeAmount, 'Stake amount too high');

    race.rewardPool += amount;
    rocket.totalStake += amount;
    userStakeForRocket[raceId][rocketId][msg.sender] += amount;
    _addClaimableUserRaceId(raceId, msg.sender);
    _addUserForRaceId(raceId, msg.sender);

    magic.transferFrom(msg.sender, address(this), amount);

    emit StakedOnRocket(raceId, rocketId, msg.sender, amount);
  }

  function _addClaimableUserRaceId(uint256 raceId, address user) internal {
    if (!_arrayHasId(claimableUserRaceIds[user], raceId)) {
      claimableUserRaceIds[user].push(raceId);
    }
  }

  function _removeClaimableUserRaceId(uint256 raceId, address user) internal {
    _removeArrayItem(claimableUserRaceIds[user], raceId);
  }

  function _addUserForRaceId(uint256 raceId, address user) internal {
    if (!userForRaceId[raceId][user]) {
      userForRaceId[raceId][user] = true;
      usersForRaceId[raceId].push(user);
    }
  }

  function _removeArrayItem(uint256[] storage arr, uint256 item) internal {
    for (uint256 i; i < arr.length; i++) {
      if (arr[i] == item) {
        arr[i] = arr[arr.length - 1];
        arr.pop();
        break;
      }
    }
  }

  function getUsersForRaceId(uint256 raceId) external view returns (address[] memory) {
    return usersForRaceId[raceId];
  }

  function getStakeAmountForStaker(
    uint256 raceId,
    uint8 rocketId,
    address staker
  ) external view returns (uint256) {
    return userStakeForRocket[raceId][rocketId][staker];
  }

  function applyBoost(uint256 raceId, uint8 rocketId) external {
    Race storage race = races[raceId];
    require(!race.finished, 'Race already finished');
    if (race.revealBlock > 0) {
      require(block.number < race.revealBlock, 'Reveal block has already been mined');
    }
    Rocket storage rocket = race.rockets[rocketId];
    require(rocket.totalBoosts < maxBoostsPerRocket, 'Max number of boosts reached');

    rocket.totalBoosts += 1;
    race.rewardPool += race.configSnapshot.boostPrice;

    magic.transferFrom(msg.sender, address(this), race.configSnapshot.boostPrice);

    emit BoostApplied(raceId, rocketId, msg.sender);
  }

  function startRace(uint256 raceId) public {
    Race storage race = races[raceId];
    require(!race.finished, 'Race already finished');
    require(!race.started, 'Race already started');
    require(race.configSnapshot.maxRockets == race.rockets.length, 'Race can only be started with full roster');

    race.blastOffTimestamp = _calcClosestBlastOffTimestamp(block.timestamp, timeParams.blastOffTimes);
    uint256 revealTimestamp = _calcRevealTimestamp(race.blastOffTimestamp, timeParams.revealDelayMinutes);
    race.revealBlock = block.number + _calcBlockDiff(block.timestamp, revealTimestamp);
    race.started = true;

    emit RaceStarted(raceId, race.blastOffTimestamp, race.revealBlock);
  }

  function _calcRevealTimestamp(uint256 _blastOffTimestamp, uint8 _revealDelayMinutes)
    public
    pure
    returns (uint256 revealTimestamp)
  {
    return _blastOffTimestamp + (uint256(_revealDelayMinutes) * 1 minutes);
  }

  function _calcClosestBlastOffTimestamp(uint256 _currentTimestamp, uint32[] memory _blastOffTimes)
    public
    pure
    returns (uint256 blastOffTimestamp)
  {
    uint256 startOfHour = (_currentTimestamp / 1 hours) * 1 hours;
    uint256 startOfDay = (startOfHour / 1 days) * 1 days;
    uint256 currentTimeOfDay = _currentTimestamp - startOfDay;

    for (uint8 i = 0; i < _blastOffTimes.length; i++) {
      if (currentTimeOfDay < _blastOffTimes[i]) {
        return startOfDay + uint256(_blastOffTimes[i]);
      }
    }

    // too late, move blast off to earliest time tomorrow
    return startOfDay + 1 days + uint256(_blastOffTimes[0]);
  }

  function _calcBlockDiff(uint256 startTimestamp, uint256 endTimestamp) internal view returns (uint256 blockDiff) {
    require(startTimestamp < endTimestamp, 'Start timestamp must be smaller than start timestamp');
    return ((endTimestamp - startTimestamp) * 1000) / timeParams.blockTimeMillis;
  }

  function finishRace(uint256 raceId) public {
    Race storage race = races[raceId];
    require(!race.finished, 'Race already finished');
    require(race.started, 'Race must be started first');
    require(block.number > race.revealBlock, 'Race can only be finished after revealBlock has been mined');

    race.finished = true;
    race.winner = _calcWinner(race, race.revealBlock);
    race.rewardPool -= race.configSnapshot.revealBounty;

    _removeArrayItem(activeRaceIds, raceId);

    if (autoCreateNextRace) {
      _createRace();
    }

    _assignWinnings(race);

    magic.transfer(msg.sender, race.configSnapshot.revealBounty);

    emit RaceFinished(
      raceId,
      race.winner,
      race.rockets[race.winner].nft,
      race.rockets[race.winner].nftId,
      race.rockets[race.winner].rocketeer
    );
  }

  function _calcWinner(Race storage race, uint256 blockNumber) internal view returns (uint8) {
    uint16[] memory winThresholds = new uint16[](race.configSnapshot.maxRockets);
    uint16 totalWeight;

    for (uint8 i = 0; i < race.configSnapshot.maxRockets; i++) {
      uint8 weight = _calcWeight(race.rockets[i].totalBoosts, race.configSnapshot.boostAmount, blockNumber - i);
      totalWeight += weight;
      winThresholds[i] = totalWeight;
    }

    uint256 randomness = uint256(blockhash(blockNumber)) % totalWeight;

    for (uint8 i = 0; i < winThresholds.length; i++) {
      if (randomness < winThresholds[i]) {
        return i;
      }
    }

    revert('No winner was found. This should not have happened.');
  }

  function _calcWeight(
    uint8 totalBoosts,
    uint8 boostAmount,
    uint256 blockNumber
  ) internal view returns (uint8 weight) {
    weight = 100;
    uint256 randomness = uint256(blockhash(blockNumber));
    uint8 minWeightPreBoost = 1 + boostAmount;
    uint8 maxWeightPreBoost = weight * 2 - 1 - boostAmount;

    for (uint8 b = 0; b < totalBoosts; b++) {
      // read b-th bit
      uint8 result = uint8((randomness >> b) & 1);
      if (result == 1 && weight <= maxWeightPreBoost) {
        weight += boostAmount;
      } else if (result == 0 && weight >= minWeightPreBoost) {
        weight -= boostAmount;
      }
    }

    return weight;
  }

  function _assignWinnings(Race storage race) internal {
    uint256 devFee = (race.rewardPool * race.configSnapshot.devFeePercent) / 100;
    race.rewardPool -= devFee;
    uint256 rocketsShare = (race.rewardPool * race.configSnapshot.rocketsSharePercent) / 100;
    uint256 poolRemainder = race.rewardPool - rocketsShare;
    race.rewardPerShare = (poolRemainder * 1 ether) / race.rockets[race.winner].totalStake;
    race.winningRocketShare = (rocketsShare * race.configSnapshot.winningRocketSharePercent) / 100;
    race.otherRocketsShare = (rocketsShare - race.winningRocketShare) / (race.rockets.length - 1);

    magic.transfer(beneficiary, devFee);
  }

  function calcClaimableAmount(address user, uint256 raceId) public view returns (uint256 amount) {
    uint256 rocketeerReward = calcRocketeerReward(raceId, user);
    return calcStakeReward(raceId, user) + rocketeerReward;
  }

  function calcClaimableAmountMulti(address user, uint256[] memory raceIds) public view returns (uint256 amount) {
    for (uint256 i = 0; i < raceIds.length; i++) {
      amount += calcClaimableAmount(user, raceIds[i]);
    }
    return amount;
  }

  function calcClaimableAmountAll(address user) public view returns (uint256 amount) {
    return calcClaimableAmountMulti(user, claimableUserRaceIds[user]);
  }

  function calcStakeReward(uint256 raceId, address staker) public view returns (uint256) {
    Race storage race = races[raceId];

    return (race.rewardPerShare * userStakeForRocket[raceId][race.winner][staker]) / 1 ether;
  }

  function calcRocketeerReward(uint256 raceId, address rocketeer) public view returns (uint256) {
    Race storage race = races[raceId];
    uint256 reward;

    for (uint8 i = 0; i < race.rockets.length; i++) {
      if (race.rockets[i].rocketeer == rocketeer) {
        if (race.winner == i) {
          reward += race.winningRocketShare;
        } else {
          reward += race.otherRocketsShare;
        }
      }
    }

    return reward;
  }

  function claim(uint256 raceId) public {
    Race storage race = races[raceId];
    if (!race.finished) {
      return;
    }
    if (!_arrayHasId(claimableUserRaceIds[msg.sender], raceId)) {
      return;
    }

    _removeClaimableUserRaceId(raceId, msg.sender);

    _claimRocketeerReward(race, msg.sender);
    _claimStakeReward(race.id, msg.sender);
  }

  function _claimStakeReward(uint256 raceId, address user) internal {
    uint256 stakeReward = calcStakeReward(raceId, user);

    if (stakeReward > 0) {
      magic.transfer(user, stakeReward);

      emit StakeRewardClaimed(raceId, user, stakeReward);
    }
  }

  function _claimRocketeerReward(Race storage race, address user) internal {
    uint256 rocketeerReward = calcRocketeerReward(race.id, msg.sender);

    if (rocketeerReward > 0) {
      magic.transfer(user, rocketeerReward);

      emit RocketeerRewardClaimed(race.id, user, rocketeerReward);
    }
  }

  function claimMulti(uint256[] memory raceIds) public {
    for (uint i = 0; i < raceIds.length; i++) {
      claim(raceIds[i]);
    }
  }

  function claimAll() external {
    claimMulti(claimableUserRaceIds[msg.sender]);
  }

  function getBlockNumber() public view returns (uint256) {
    return block.number;
  }

  function getBlockhash(uint n) public view returns (bytes32) {
    return blockhash(n);
  }

  function getBlockhashUint(uint n) public view returns (uint256) {
    return uint256(blockhash(n));
  }
}

