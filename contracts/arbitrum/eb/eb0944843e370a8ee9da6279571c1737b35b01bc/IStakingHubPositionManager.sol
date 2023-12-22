// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IStakingHubPositionManager {

  struct StakingPosition {
    uint256 amount;
    uint256 unclaimedReward;
    uint256 createdAt;
    uint256 updatedAt;
  }

  /**
   * @notice Return the staking position for the given id
   * @dev Will revert :
   *        - TokenId doesn't exist
   * @param tokenId The id of the staking position token
   * @return stakingPosition position The staking position itself
   */
  function getStakingPosition(uint256 tokenId) external view returns (StakingPosition memory stakingPosition);
}
