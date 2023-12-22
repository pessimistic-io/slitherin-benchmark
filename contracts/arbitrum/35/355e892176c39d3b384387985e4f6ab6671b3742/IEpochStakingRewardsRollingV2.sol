// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IEpochStakingRewardsRollingV2 {
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

  function claimDetails(
    address _user,
    uint32 _epoch
  ) external view returns (bool, uint32, uint96, uint96);

  function claimRewardsFor(address _user, uint32 _epoch) external;

  function claimRewards() external;

  function claimRewards(address _user) external;

  function epochRewards(
    uint32 _epoch
  ) external view returns (uint32 _addedAtTimestamp, uint96 _plsDpx, uint96 _plsJones);

  function totalPlsDpxRewards() external view returns (uint96);

  function totalPlsJonesRewards() external view returns (uint96);

  event DepositRewards(uint32 indexed _epoch, uint96 _plsDpxRewards, uint96 _plsJonesRewards);
  event ClaimRewards(
    address indexed _user,
    uint32 indexed _epoch,
    uint256 _plsDpxRewards,
    uint256 _plsJonesRewards
  );
}

