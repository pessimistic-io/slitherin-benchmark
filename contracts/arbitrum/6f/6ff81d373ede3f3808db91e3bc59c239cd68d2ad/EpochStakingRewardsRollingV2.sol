// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./IEpochStakingRewardsRollingV2.sol";
import "./IEpochStaking.sol";

contract EpochStakingRewardsRollingV2 is
  Initializable,
  PausableUpgradeable,
  OwnableUpgradeable,
  UUPSUpgradeable,
  IEpochStakingRewardsRollingV2
{
  uint256 public constant EPOCH_DURATION = 2_628_000 seconds;
  IERC20Upgradeable public constant plsDPX =
    IERC20Upgradeable(0xF236ea74B515eF96a9898F5a4ed4Aa591f253Ce1);
  IERC20Upgradeable public constant plsJONES =
    IERC20Upgradeable(0xe7f6C3c1F0018E4C08aCC52965e5cbfF99e34A44);
  IEpochStaking public constant staking = IEpochStaking(0x27Aaa9D562237BF8E024F9b21DE177e20ae50c05);
  IEpochStakingRewardsRollingV2 public constant OLD_STAKING_REWARDS =
    IEpochStakingRewardsRollingV2(0x50B3091b4188edFA3589B341aDFb078edB93AdDd);

  uint96 public totalPlsDpxRewards;
  uint96 public totalPlsJonesRewards;

  // Address => Epoch => Claim Details
  mapping(address => mapping(uint32 => ClaimDetails)) public claimDetails;

  // Epoch => Reward
  mapping(uint32 => Reward) public epochRewards;

  mapping(address => bool) public migrated;
  mapping(address => bool) public isHandler;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public initializer {
    __Pausable_init();
    __Ownable_init();
    __UUPSUpgradeable_init();

    _migrateStorage();
  }

  /** VIEWS */
  function _calculateShare(
    uint112 _userStaked,
    uint112 _totalStaked,
    uint256 _rewardAmountForEpoch
  ) private pure returns (uint256) {
    unchecked {
      return (_userStaked * _rewardAmountForEpoch) / _totalStaked;
    }
  }

  function claimRewards() external {
    _migrateClaimDetails(msg.sender);

    uint32 _currentEpoch = staking.currentEpoch();
    address _user = msg.sender;

    for (uint32 i = 0; i < _currentEpoch; i = _unsafeInc(i)) {
      if (!claimDetails[_user][i].fullyClaimed) {
        _claimRewardsFor(_user, i);
      }
    }
  }

  function migrateClaimDetails() external whenNotPaused {
    _migrateClaimDetails(msg.sender);
  }

  /** OPERATOR */

  function claimRewards(address _user) external {
    require(isHandler[msg.sender], 'Unauthorized');
    uint32 _currentEpoch = staking.currentEpoch();

    for (uint32 i = 0; i < _currentEpoch; i = _unsafeInc(i)) {
      if (!claimDetails[_user][i].fullyClaimed) {
        _claimRewardsFor(_user, i);
      }
    }
  }

  function claimRewardsFor(address _user, uint32 _epoch) external {
    require(isHandler[msg.sender], 'Unauthorized');
    _claimRewardsFor(_user, _epoch);
  }

  function pendingRewardsFor(
    address _user,
    uint32 _epoch
  ) public view returns (uint256 _plsDpxRewards, uint256 _plsJonesRewards) {
    ClaimDetails memory _claimDetails = claimDetails[_user][_epoch];
    Reward memory _rewardsForEpoch = epochRewards[_epoch];

    // rewards not added || already fully claimed
    if (_rewardsForEpoch.addedAtTimestamp == 0 || _claimDetails.fullyClaimed) {
      return (0, 0);
    }

    uint112 _userStaked;
    (uint112 _stakedAmount, uint32 _lastCheckpoint) = staking.stakedDetails(_user);

    if (_lastCheckpoint > _epoch) {
      _userStaked = staking.stakedCheckpoints(_user, _epoch);
    } else {
      // simulate checkpointing
      _userStaked = _stakedAmount;
    }

    (, , uint112 _totalStaked) = staking.epochCheckpoints(_epoch);

    // user total reward allocation for epoch
    uint256 _plsDpxRewardAllocForEpoch = _calculateShare(
      _userStaked,
      _totalStaked,
      _rewardsForEpoch.plsDpx
    );

    uint256 _plsJonesRewardAllocForEpoch = _calculateShare(
      _userStaked,
      _totalStaked,
      _rewardsForEpoch.plsJones
    );

    uint256 duration;
    // rewards are vested for currentEpoch - 1
    if (_claimDetails.lastClaimedTimestamp == 0) {
      duration = block.timestamp - _rewardsForEpoch.addedAtTimestamp;
    } else {
      duration = block.timestamp - _claimDetails.lastClaimedTimestamp;
    }

    if (duration > EPOCH_DURATION) duration = EPOCH_DURATION;

    _plsDpxRewards = (_plsDpxRewardAllocForEpoch * duration) / EPOCH_DURATION;
    _plsJonesRewards = (_plsJonesRewardAllocForEpoch * duration) / EPOCH_DURATION;

    if (
      _plsDpxRewards != 0 &&
      _claimDetails.plsDpxClaimedAmt + _plsDpxRewards >= _plsDpxRewardAllocForEpoch
    ) {
      _plsDpxRewards = _plsDpxRewardAllocForEpoch - _claimDetails.plsDpxClaimedAmt;
    }

    if (
      _plsJonesRewards != 0 &&
      _claimDetails.plsJonesClaimedAmt + _plsJonesRewards >= _plsJonesRewardAllocForEpoch
    ) {
      _plsJonesRewards = _plsJonesRewardAllocForEpoch - _claimDetails.plsJonesClaimedAmt;
    }
  }

  function pendingRewards(
    address _user
  ) external view returns (uint256 _pendingPlsDpx, uint256 _pendingPlsJones) {
    // rewards are retroactive, there are no rewards for current epoch, hence - 1
    uint256 _epoch = staking.currentEpoch();

    for (uint32 i = 0; i < _epoch; i = _unsafeInc(i)) {
      if (!claimDetails[_user][i].fullyClaimed) {
        (uint256 d, uint256 j) = pendingRewardsFor(_user, i);
        _pendingPlsDpx += d;
        _pendingPlsJones += j;
      }
    }
  }

  function _unsafeInc(uint32 x) private pure returns (uint32) {
    unchecked {
      return x + 1;
    }
  }

  function _claimRewardsFor(address _user, uint32 _epoch) internal whenNotPaused {
    ClaimDetails memory _claimDetails = claimDetails[_user][_epoch];
    Reward memory _rewardsForEpoch = epochRewards[_epoch];

    if (_rewardsForEpoch.addedAtTimestamp == 0) {
      return;
    }

    (, , uint112 _totalStaked) = staking.epochCheckpoints(_epoch);

    uint112 _userStaked;
    {
      (uint112 _stakedAmount, uint32 _lastCheckpoint) = staking.stakedDetails(_user);

      if (_lastCheckpoint > _epoch) {
        _userStaked = staking.stakedCheckpoints(_user, _epoch);
      } else {
        // simulate checkpointing
        _userStaked = _stakedAmount;
      }
    }

    uint256 _plsDpxRewardAllocForEpoch = _calculateShare(
      _userStaked,
      _totalStaked,
      _rewardsForEpoch.plsDpx
    );

    uint256 _plsJonesRewardAllocForEpoch = _calculateShare(
      _userStaked,
      _totalStaked,
      _rewardsForEpoch.plsJones
    );

    uint256 duration;
    {
      // rewards are vested for currentEpoch - 1
      if (_claimDetails.lastClaimedTimestamp == 0) {
        duration = block.timestamp - _rewardsForEpoch.addedAtTimestamp;
      } else {
        duration = block.timestamp - _claimDetails.lastClaimedTimestamp;
      }

      if (duration > EPOCH_DURATION) duration = EPOCH_DURATION;
    }

    uint256 _claimablePlsDpx = (_plsDpxRewardAllocForEpoch * duration) / EPOCH_DURATION;

    uint256 _claimablePlsJones = (_plsJonesRewardAllocForEpoch * duration) / EPOCH_DURATION;

    if (
      _claimablePlsDpx != 0 &&
      _claimDetails.plsDpxClaimedAmt + _claimablePlsDpx > _plsDpxRewardAllocForEpoch
    ) {
      _claimablePlsDpx = _plsDpxRewardAllocForEpoch - _claimDetails.plsDpxClaimedAmt;
    }

    if (
      _claimablePlsJones != 0 &&
      _claimDetails.plsJonesClaimedAmt + _claimablePlsJones > _plsJonesRewardAllocForEpoch
    ) {
      _claimablePlsJones = _plsJonesRewardAllocForEpoch - _claimDetails.plsJonesClaimedAmt;
    }

    bool _fullyClaimed = (_claimDetails.plsDpxClaimedAmt + _claimablePlsDpx ==
      _plsDpxRewardAllocForEpoch) &&
      (_claimDetails.plsJonesClaimedAmt + _claimablePlsJones == _plsJonesRewardAllocForEpoch);

    unchecked {
      claimDetails[_user][_epoch] = ClaimDetails({
        fullyClaimed: _fullyClaimed,
        plsDpxClaimedAmt: _claimDetails.plsDpxClaimedAmt + uint96(_claimablePlsDpx),
        plsJonesClaimedAmt: _claimDetails.plsJonesClaimedAmt + uint96(_claimablePlsJones),
        lastClaimedTimestamp: uint32(block.timestamp)
      });
    }

    plsDPX.transfer(_user, _claimablePlsDpx);
    plsJONES.transfer(_user, _claimablePlsJones);

    emit ClaimRewards(_user, _epoch, _claimablePlsDpx, _claimablePlsJones);
  }

  // Migration
  function _migrateStorage() internal {
    uint32 epoch = 4; // migrate epochs 0 - 3

    totalPlsDpxRewards = OLD_STAKING_REWARDS.totalPlsDpxRewards();
    totalPlsJonesRewards = OLD_STAKING_REWARDS.totalPlsJonesRewards();

    unchecked {
      for (uint32 i = 0; i < epoch; i++) {
        (uint32 _addedAtTs, uint96 _plsDpx, uint96 _plsJones) = OLD_STAKING_REWARDS.epochRewards(i);

        epochRewards[i] = Reward({
          addedAtTimestamp: _addedAtTs,
          plsDpx: _plsDpx,
          plsJones: _plsJones
        });
      }
    }
  }

  function _migrateClaimDetails(address _user) internal {
    if (migrated[_user]) {
      return;
    }

    uint32 epoch = 4; // migrate epochs 0 - 3

    for (uint32 i = 0; i < epoch; i = _unsafeInc(i)) {
      (
        bool _fullyClaimed,
        uint32 _lastClaimedTs,
        uint96 _plsDpxClaimed,
        uint96 _plsJonesClaimed
      ) = OLD_STAKING_REWARDS.claimDetails(_user, i);

      uint96 correctPlsDpxAlloc;
      uint96 correctPlsJonesAlloc;
      {
        uint112 _userStaked = staking.stakedCheckpoints(_user, i);
        (, , uint112 _totalStaked) = staking.epochCheckpoints(i);
        Reward memory _rewardsForEpoch = epochRewards[i];

        correctPlsDpxAlloc = uint96(
          _calculateShare(_userStaked, _totalStaked, _rewardsForEpoch.plsDpx)
        );

        correctPlsJonesAlloc = uint96(
          _calculateShare(_userStaked, _totalStaked, _rewardsForEpoch.plsJones)
        );
      }

      uint96 correctPlsDpxClaimedAmt = _plsDpxClaimed;
      // if overclaimed plsDpx
      if (_plsDpxClaimed > correctPlsDpxAlloc) {
        // set max claim
        correctPlsDpxClaimedAmt = correctPlsDpxAlloc;
      }

      uint96 correctPlsJonesClaimedAmt = _plsJonesClaimed;
      // if overclaimed plsJones
      if (_plsJonesClaimed > correctPlsJonesAlloc) {
        // set max claim
        correctPlsJonesClaimedAmt = correctPlsJonesAlloc;
      }

      _fullyClaimed =
        correctPlsDpxClaimedAmt == correctPlsDpxAlloc &&
        correctPlsJonesClaimedAmt == correctPlsJonesAlloc;

      claimDetails[_user][i] = ClaimDetails({
        fullyClaimed: _fullyClaimed,
        lastClaimedTimestamp: _lastClaimedTs,
        plsDpxClaimedAmt: correctPlsDpxClaimedAmt,
        plsJonesClaimedAmt: correctPlsJonesClaimedAmt
      });
    }

    migrated[_user] = true;
  }

  /** OWNER FUNCTIONS */
  function setPause(bool _isPaused) external onlyOwner {
    if (_isPaused) {
      _pause();
    } else {
      _unpause();
    }
  }

  /// @dev Retrieve stuck funds or new reward tokens
  function retrieve(IERC20Upgradeable token) external onlyOwner {
    if ((address(this).balance) != 0) {
      payable(owner()).transfer(address(this).balance);
    }

    token.transfer(owner(), token.balanceOf(address(this)));
  }

  function depositRewardsForEpoch(uint32 _epoch, uint96 _plsDpx, uint96 _plsJones) public {
    require(msg.sender == owner() || msg.sender == address(this), 'Unauthorized');
    require(epochRewards[_epoch].addedAtTimestamp == 0, 'Rewards already added');
    (, uint32 endedAt, ) = staking.epochCheckpoints(_epoch);
    require(endedAt > 0, 'Epoch is still current');

    epochRewards[_epoch] = Reward({
      addedAtTimestamp: endedAt,
      plsDpx: _plsDpx,
      plsJones: _plsJones
    });

    totalPlsJonesRewards += _plsJones;
    totalPlsDpxRewards += _plsDpx;

    plsDPX.transferFrom(msg.sender, address(this), _plsDpx);
    plsJONES.transferFrom(msg.sender, address(this), _plsJones);

    emit DepositRewards(_epoch, _plsDpx, _plsJones);
  }

  function updateHandler(address _handler, bool _isActive) external onlyOwner {
    isHandler[_handler] = _isActive;
  }

  /// @dev deposit rewards for previous epoch
  function depositRewards(uint96 _plsDpx, uint96 _plsJones) external onlyOwner {
    uint32 _epoch = staking.currentEpoch();
    require(_epoch > 0, 'epoch = 0'); // must wait for 1 epoch to pass before adding rewards
    depositRewardsForEpoch(_epoch - 1, _plsDpx, _plsJones);
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

