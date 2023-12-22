// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "./IERC20.sol";
import "./IERC721.sol";
import "./IERC721Receiver.sol";

interface IYieldBooster {
  function deallocateAllFromPool(address userAddress, uint256 tokenId) external;

  function getMultiplier(
    address poolAddress,
    uint256 maxBoostMultiplier,
    uint256 amount,
    uint256 totalPoolSupply,
    uint256 allocatedAmount
  ) external view returns (uint256);
}

interface IDividendsV2 {
  function totalAllocation() external view returns (uint256);

  function usersAllocation(address user) external view returns (uint256);

  function pendingDividendsAmount(address token, address user) external view returns (uint256);

  function currentCycleStartTime() external view returns (uint256);

  function nextCycleStartTime() external view returns (uint256);

  function harvestAllDividends() external;
}

interface INFTHandler is IERC721Receiver {
  function onNFTHarvest(
    address operator,
    address to,
    uint256 tokenId,
    uint256 grailAmount,
    uint256 xGrailAmount
  ) external returns (bool);

  function onNFTAddToPosition(address operator, uint256 tokenId, uint256 lpAmount) external returns (bool);

  function onNFTWithdraw(address operator, uint256 tokenId, uint256 lpAmount) external returns (bool);
}

interface IXGrailTokenUsage is IERC20 {
  function usageAllocations(address userAddress, address usageAddress) external view returns (uint256 allocation);

  function redeem(uint256 xGrailAmount, uint256 duration) external;

  function finalizeRedeem(uint256 redeemIndex) external;

  function cancelRedeem(uint256 redeemIndex) external;

  function maxRedeemDuration() external view returns (uint256);

  function minRedeemDuration() external view returns (uint256);

  function getUserRedeem(
    address userAddress,
    uint256 redeemIndex
  )
    external
    view
    returns (
      uint256 grailAmount,
      uint256 xGrailAmount,
      uint256 endTime,
      address dividendsContract,
      uint256 dividendsAllocation
    );

  function getUserRedeemsLength(address userAddress) external view returns (uint256);

  function approveUsage(IXGrailTokenUsage usage, uint256 amount) external;

  function allocate(address usageAddress, uint256 amount, bytes calldata usageData) external;

  function deallocate(address usageAddress, uint256 amount, bytes calldata usageData) external;
}

interface INFTPool is IERC721 {
  function exists(uint256 tokenId) external view returns (bool);

  function lastTokenId() external view returns (uint256);

  function getPoolInfo()
    external
    view
    returns (
      address lpToken,
      address grailToken,
      address sbtToken,
      uint256 lastRewardTime,
      uint256 accRewardsPerShare,
      uint256 lpSupply,
      uint256 lpSupplyWithMultiplier,
      uint256 allocPoint
    );

  function getStakingPosition(
    uint256 tokenId
  )
    external
    view
    returns (
      uint256 amount,
      uint256 amountWithMultiplier,
      uint256 startLockTime,
      uint256 lockDuration,
      uint256 lockMultiplier,
      uint256 rewardDebt,
      uint256 boostPoints,
      uint256 totalMultiplier
    );

  function addToPosition(uint256 tokenId, uint256 amountToAdd) external;

  function createPosition(uint256 amount, uint256 lockDuration) external;

  function withdrawFromPosition(uint256 tokenId, uint256 amountToWithdraw) external;

  function harvestPosition(uint256 tokenId) external;

  function harvestPositionTo(uint256 tokenId, address to) external;

  function harvestPositionsTo(uint256[] calldata tokenIds, address to) external;

  function pendingRewards(uint256 tokenId) external view returns (uint256);

  function xGrailRewardsShare() external view returns (uint256);

  function renewLockPosition(uint256 tokenId) external;

  function lockPosition(uint256 tokenId, uint256 lockDuration) external;

  /**
   * @dev Returns expected multiplier for a "lockDuration" duration lock (result is *1e4)
   */
  function getMultiplierByLockDuration(uint256 lockDuration) external view returns (uint256);

  /**
   * @dev Returns bonus multiplier from YieldBooster contract for given "amount" (LP token staked) and "boostPoints" (result is *1e4)
   */
  function getMultiplierByBoostPoints(uint256 amount, uint256 boostPoints) external view returns (uint256);
}

interface INitroPool {
  function withdraw(uint256 tokenId) external;

  function nftPool() external view returns (address);

  function tokenIdOwner(uint256) external view returns (address);

  function harvest() external;

  function pendingRewards(address) external view returns (uint pending1, uint pending2);

  function rewardsToken1()
    external
    view
    returns (address token, uint amount, uint remainingAmount, uint accRewardsPerShare);

  function rewardsToken1PerSecond() external view returns (uint256);

  function rewardsToken2()
    external
    view
    returns (address token, uint amount, uint remainingAmount, uint accRewardsPerShare);

  function rewardsToken2PerSecond() external view returns (uint256);

  function emergencyWithdraw(uint256 tokenId) external;

  function totalDepositAmount() external view returns (uint256);

  function userInfo(
    address user
  )
    external
    view
    returns (
      uint256 totalDepositAmount, // Save total deposit amount
      uint256 rewardDebtToken1,
      uint256 rewardDebtToken2,
      uint256 pendingRewardsToken1, // can't be harvested before harvestStartTime
      uint256 pendingRewardsToken2 // can't be harvested before harvestStartTime
    );
}

interface ICamelotPair is IERC20 {
  function getReserves()
    external
    view
    returns (uint112 reserve0, uint112 reserve1, uint16 token0feePercent, uint16 token1FeePercent);

  function token0() external view returns (address);

  function token1() external view returns (address);
}

