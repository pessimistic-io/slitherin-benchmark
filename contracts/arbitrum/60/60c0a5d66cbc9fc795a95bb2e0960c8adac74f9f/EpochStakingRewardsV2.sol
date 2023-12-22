// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IERC20.sol";
import "./Ownable.sol";

interface IPlutusEpochStaking {
  function stakedDetails(address _user) external view returns (uint112 amount, uint32 lastCheckpoint);

  function epochCheckpoints(uint32 _epoch)
    external
    view
    returns (
      uint32 startedAt,
      uint32 endedAt,
      uint112 totalStaked
    );

  function currentTotalStaked() external view returns (uint112);

  function stakedCheckpoints(address _addr, uint32 _epoch) external view returns (uint112 _amount);
}

interface IEpochStakingRewards {
  function claimDetails(address _addr, uint32 _epoch)
    external
    view
    returns (
      bool _fullyClaimed,
      uint32 _lastClaimedTimestamp,
      uint96 _plsDpxClaimedAmt,
      uint96 _plsJonesClaimedAmt
    );

  function epochRewards(uint32 _epoch)
    external
    view
    returns (
      uint32 _addedAtTimestamp,
      uint96 _plsDpx,
      uint96 _plsJones
    );

  function epoch() external view returns (uint32);

  function totalPlsDpxRewards() external view returns (uint96);

  function totalPlsJonesRewards() external view returns (uint96);
}

contract EpochStakingRewardsV2 is Ownable {
  uint256 private constant EPOCH_DURATION = 2_628_000 seconds;

  IERC20 public immutable plsDPX;
  IERC20 public immutable plsJONES;
  IPlutusEpochStaking public immutable staking;
  IEpochStakingRewards private immutable oldRewards;

  struct Reward {
    uint32 addedAtTimestamp;
    uint96 plsDpx;
    uint96 plsJones;
  }

  struct ClaimDetails {
    bool fullyClaimed;
    uint32 lastClaimedTimestamp;
    uint96 plsDpxClaimedAmt;
    uint96 plsJonesClaimedAmt;
  }

  uint32 public epoch;
  uint96 public totalPlsDpxRewards;
  uint96 public totalPlsJonesRewards;

  // Address => Epoch => Claim Details
  mapping(address => mapping(uint32 => ClaimDetails)) public claimDetails;

  // Epoch => Reward
  mapping(uint32 => Reward) public epochRewards;

  mapping(address => bool) public migrated;

  constructor(
    address _plsDpx,
    address _plsJones,
    address _staking,
    address _oldRewards
  ) {
    plsDPX = IERC20(_plsDpx);
    plsJONES = IERC20(_plsJones);
    staking = IPlutusEpochStaking(_staking);
    oldRewards = IEpochStakingRewards(_oldRewards);
    _migrateStorage();
  }

  function claimAll() external {
    _migrateClaimDetails(msg.sender);
    uint32 _epoch = epoch;

    unchecked {
      for (uint32 i = 0; i <= _epoch; i++) {
        if (!claimDetails[msg.sender][i].fullyClaimed) {
          _claimRewards(i);
        }
      }
    }
  }

  function _claimRewards(uint32 _epoch) internal {
    ClaimDetails memory _claimDetails = claimDetails[msg.sender][_epoch];
    Reward memory rewardsForEpoch = epochRewards[_epoch];

    // User rewards for epoch
    uint256 userPlsDpxShare = calculateShare(msg.sender, _epoch, rewardsForEpoch.plsDpx);
    uint256 userPlsJonesShare = calculateShare(msg.sender, _epoch, rewardsForEpoch.plsJones);

    require(userPlsDpxShare > 0 || userPlsJonesShare > 0, 'No rewards');

    uint256 claimablePlsDpx; // user portion claimable
    uint256 claimablePlsJones; // user portion claimable

    // Claim prorated amount for current epoch
    uint256 vestedDuration;

    unchecked {
      if (_claimDetails.lastClaimedTimestamp > rewardsForEpoch.addedAtTimestamp) {
        vestedDuration = block.timestamp - _claimDetails.lastClaimedTimestamp;
      } else {
        vestedDuration = block.timestamp - rewardsForEpoch.addedAtTimestamp;
      }

      claimablePlsDpx += (userPlsDpxShare * vestedDuration) / EPOCH_DURATION;
      claimablePlsJones += (userPlsJonesShare * vestedDuration) / EPOCH_DURATION;
    }

    bool _fullyClaimed;

    if (claimablePlsDpx > userPlsDpxShare - _claimDetails.plsDpxClaimedAmt) {
      // if claimable asset calculated is > claimable amt
      claimablePlsDpx = uint96(userPlsDpxShare - _claimDetails.plsDpxClaimedAmt);
      _fullyClaimed = true;
    } else {
      claimablePlsDpx = uint96(claimablePlsDpx);
    }

    if (claimablePlsJones > userPlsJonesShare - _claimDetails.plsJonesClaimedAmt) {
      // if claimable asset calculated is > claimable amt
      claimablePlsJones = uint96(userPlsJonesShare - _claimDetails.plsJonesClaimedAmt);
    } else {
      claimablePlsJones = uint96(claimablePlsJones);
    }

    // Update user claim details
    unchecked {
      claimDetails[msg.sender][_epoch] = ClaimDetails({
        fullyClaimed: _fullyClaimed,
        plsDpxClaimedAmt: _claimDetails.plsDpxClaimedAmt + uint96(claimablePlsDpx),
        plsJonesClaimedAmt: _claimDetails.plsJonesClaimedAmt + uint96(claimablePlsJones),
        lastClaimedTimestamp: uint32(block.timestamp)
      });
    }

    plsDPX.transfer(msg.sender, claimablePlsDpx);
    plsJONES.transfer(msg.sender, claimablePlsJones);

    emit ClaimRewards(msg.sender);
  }

  function _migrateStorage() internal {
    uint32 _epoch = oldRewards.epoch();
    epoch = _epoch;
    totalPlsDpxRewards = oldRewards.totalPlsDpxRewards();
    totalPlsJonesRewards = oldRewards.totalPlsJonesRewards();

    unchecked {
      for (uint32 i = 0; i <= _epoch; i++) {
        (uint32 _addedAtTs, uint96 _plsDpx, uint96 _plsJones) = oldRewards.epochRewards(i);
        epochRewards[i] = Reward({ addedAtTimestamp: _addedAtTs, plsDpx: _plsDpx, plsJones: _plsJones });
      }
    }
  }

  function _migrateClaimDetails(address _user) internal {
    if (migrated[_user]) {
      return;
    }

    unchecked {
      for (uint32 i = 0; i <= epoch; i++) {
        (bool _fullyClaimed, uint32 _lastClaimedTs, uint96 _plsDpxClaimed, uint96 _plsJonesClaimed) = oldRewards
          .claimDetails(_user, i);

        claimDetails[_user][i] = ClaimDetails({
          fullyClaimed: _fullyClaimed,
          lastClaimedTimestamp: _lastClaimedTs,
          plsDpxClaimedAmt: _plsDpxClaimed,
          plsJonesClaimedAmt: _plsJonesClaimed
        });
      }
    }

    migrated[_user] = true;
  }

  /** VIEWS */
  function getAmount(address _addr) public view returns (bool hasWithdrawn, uint112 amount) {
    uint32 lastCheckpoint;
    (amount, lastCheckpoint) = staking.stakedDetails(_addr);
    if (lastCheckpoint > 0) {
      hasWithdrawn = true;
      amount = staking.stakedCheckpoints(_addr, 1);
    }
  }

  /// @dev Calculate share of rewards for epoch
  function calculateShare(
    address _addr,
    uint32 _epoch,
    uint256 _rewardAmt
  ) public view returns (uint256) {
    (, uint112 amount) = getAmount(_addr);
    (, , uint112 totalStaked) = staking.epochCheckpoints(_epoch);
    return (amount * _rewardAmt) / totalStaked;
  }

  function pendingRewardsFor(uint32 _epoch) public view returns (uint256 _plsDpx, uint256 _plsJones) {
    ClaimDetails memory _claimDetails = claimDetails[msg.sender][_epoch];

    if (_claimDetails.lastClaimedTimestamp == 0) {
      (
        bool __fullyClaimed,
        uint32 _lastClaimedTimestamp,
        uint96 _plsDpxClaimedAmt,
        uint96 _plsJonesClaimedAmt
      ) = oldRewards.claimDetails(msg.sender, _epoch);

      if (_lastClaimedTimestamp != 0) {
        _claimDetails = ClaimDetails({
          fullyClaimed: __fullyClaimed,
          lastClaimedTimestamp: _lastClaimedTimestamp,
          plsDpxClaimedAmt: _plsDpxClaimedAmt,
          plsJonesClaimedAmt: _plsJonesClaimedAmt
        });
      }
    }
    Reward memory rewardsForEpoch = epochRewards[_epoch];

    // User rewards for epoch
    uint256 userPlsDpxShare = calculateShare(msg.sender, _epoch, rewardsForEpoch.plsDpx);
    uint256 userPlsJonesShare = calculateShare(msg.sender, _epoch, rewardsForEpoch.plsJones);

    require(userPlsDpxShare > 0 || userPlsJonesShare > 0, 'No rewards');

    uint256 claimablePlsDpx; // user portion claimable
    uint256 claimablePlsJones; // user portion claimable

    // Claim prorated amount for current epoch
    uint256 vestedDuration;

    unchecked {
      if (_claimDetails.lastClaimedTimestamp > rewardsForEpoch.addedAtTimestamp) {
        vestedDuration = block.timestamp - _claimDetails.lastClaimedTimestamp;
      } else {
        vestedDuration = block.timestamp - rewardsForEpoch.addedAtTimestamp;
      }

      claimablePlsDpx += (userPlsDpxShare * vestedDuration) / EPOCH_DURATION;
      claimablePlsJones += (userPlsJonesShare * vestedDuration) / EPOCH_DURATION;
    }

    bool _fullyClaimed;

    if (claimablePlsDpx > userPlsDpxShare - _claimDetails.plsDpxClaimedAmt) {
      // if claimable asset calculated is > claimable amt
      claimablePlsDpx = uint96(userPlsDpxShare - _claimDetails.plsDpxClaimedAmt);
      _fullyClaimed = true;
    } else {
      claimablePlsDpx = uint96(claimablePlsDpx);
    }

    if (claimablePlsJones > userPlsJonesShare - _claimDetails.plsJonesClaimedAmt) {
      // if claimable asset calculated is > claimable amt
      claimablePlsJones = uint96(userPlsJonesShare - _claimDetails.plsJonesClaimedAmt);
    } else {
      claimablePlsJones = uint96(claimablePlsJones);
    }

    _plsDpx = claimablePlsDpx;
    _plsJones = claimablePlsJones;
  }

  function pendingRewards() external view returns (uint256 _pendingDpx, uint256 _pendingJones) {
    uint32 _epoch = epoch;

    for (uint32 i = 0; i <= _epoch; i++) {
      if (!claimDetails[msg.sender][i].fullyClaimed) {
        (uint256 d, uint256 j) = pendingRewardsFor(i);
        _pendingDpx += d;
        _pendingJones += j;
      }
    }
  }

  /** OWNER */
  /// @dev deposit to rewards contract
  function depositRewards(uint96 _plsDpx, uint96 _plsJones) external onlyOwner {
    if (totalPlsDpxRewards == 0 && totalPlsJonesRewards == 0) {
      // No op - Don't increment it for very first deposit
    } else {
      epoch += 1;
    }

    epochRewards[epoch] = Reward({ addedAtTimestamp: uint32(block.timestamp), plsDpx: _plsDpx, plsJones: _plsJones });
    totalPlsJonesRewards += _plsJones;
    totalPlsDpxRewards += _plsDpx;

    plsDPX.transferFrom(msg.sender, address(this), _plsDpx);
    plsJONES.transferFrom(msg.sender, address(this), _plsJones);

    emit DepositRewards(epoch);
  }

  /**
    Retrieve stuck funds or new reward tokens
   */
  function retrieve(IERC20 token) external onlyOwner {
    if ((address(this).balance) != 0) {
      payable(owner()).transfer(address(this).balance);
    }

    token.transfer(owner(), token.balanceOf(address(this)));
  }

  event DepositRewards(uint32 epoch);
  event ClaimRewards(address indexed _recipient);
}

