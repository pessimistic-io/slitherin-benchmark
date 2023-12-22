// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IERC721.sol";

interface ICamelotPositionHelper {
  function addLiquidityAndCreatePosition(
    address _tokenA,
    address _tokenB,
    uint256 _amountADesired,
    uint256 _amountBDesired,
    uint256 _amountAMin,
    uint256 _amountBMin,
    uint256 _deadline,
    address _to,
    INFTPool _nftPool,
    uint256 _lockDuration
  ) external;

}

interface INFTPool is IERC721 {
  function exists(uint256 tokenId) external view returns (bool);
  function hasDeposits() external view returns (bool);
  function lastTokenId() external view returns (uint256);
  function getPoolInfo() external view returns (
    address lpToken, address grailToken, address sbtToken, uint256 lastRewardTime, uint256 accRewardsPerShare,
    uint256 lpSupply, uint256 lpSupplyWithMultiplier, uint256 allocPoint
  );
  function getStakingPosition(uint256 tokenId) external view returns (
    uint256 amount, uint256 amountWithMultiplier, uint256 startLockTime,
    uint256 lockDuration, uint256 lockMultiplier, uint256 rewardDebt,
    uint256 boostPoints, uint256 totalMultiplier
  );
  function createPosition(uint256 amount, uint256 lockDuration) external;
  function boost(uint256 userAddress, uint256 amount) external;
  function unboost(uint256 userAddress, uint256 amount) external;
}

