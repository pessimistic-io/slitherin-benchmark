// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IERC20.sol";
import "./Ownable.sol";
import { IPrivateTgeHelper } from "./PrivateTgeHelper.sol";

contract PrivateTgeRewards is Ownable {
  IERC20 public immutable plsDPX; // = IERC20(0xF236ea74B515eF96a9898F5a4ed4Aa591f253Ce1);
  IERC20 public immutable plsJONES; //= IERC20(0xe7f6C3c1F0018E4C08aCC52965e5cbfF99e34A44);
  IPrivateTgeHelper public immutable helper; //= IPrivateTgeHelper(0xEC06E18b64b54470Eb423A245640600155aD3427);

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

  constructor(
    address _governance,
    address _plsDpx,
    address _plsJones,
    address _helper
  ) {
    transferOwnership(_governance);
    plsDPX = IERC20(_plsDpx);
    plsJONES = IERC20(_plsJones);
    helper = IPrivateTgeHelper(_helper);
  }

  function claimRewards(uint32 _epoch) public {
    ClaimDetails memory _claimDetails = claimDetails[msg.sender][_epoch];
    Reward memory rewardsForEpoch = epochRewards[_epoch];

    // User rewards for epoch
    uint256 userPlsDpxShare = helper.calculateShare(msg.sender, rewardsForEpoch.plsDpx);
    uint256 userPlsJonesShare = helper.calculateShare(msg.sender, rewardsForEpoch.plsJones);

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

      claimablePlsDpx += (userPlsDpxShare * vestedDuration) / helper.EPOCH();
      claimablePlsJones += (userPlsJonesShare * vestedDuration) / helper.EPOCH();
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

  function claimAll() external {
    uint32 _epoch = epoch;

    unchecked {
      for (uint32 i = 0; i <= _epoch; i++) {
        if (!claimDetails[msg.sender][i].fullyClaimed) {
          claimRewards(i);
        }
      }
    }
  }

  /** VIEWS */
  function pendingRewardsFor(uint32 _epoch) public view returns (uint256 _plsDpx, uint256 _plsJones) {
    ClaimDetails memory _claimDetails = claimDetails[msg.sender][_epoch];
    Reward memory rewardsForEpoch = epochRewards[_epoch];

    // User rewards for epoch
    uint256 userPlsDpxShare = helper.calculateShare(msg.sender, rewardsForEpoch.plsDpx);
    uint256 userPlsJonesShare = helper.calculateShare(msg.sender, rewardsForEpoch.plsJones);

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

      claimablePlsDpx += (userPlsDpxShare * vestedDuration) / helper.EPOCH();
      claimablePlsJones += (userPlsJonesShare * vestedDuration) / helper.EPOCH();
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

