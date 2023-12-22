// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

interface ILCPoolUniV2Ledger {
  function getLastRewardAmount(uint256 poolId) external view returns(uint256);
  function getUserLiquidity(address account, uint256 poolId, uint256 basketId) external view returns(uint256);

  function updateInfo(
    address acc,
    uint256 tId,
    uint256 bId,
    uint256 liquidity,
    uint256 reward,
    uint256 rewardAfter,
    uint256 exLp,
    bool increase
  ) external;

  function getSingleReward(address acc, uint256 poolId, uint256 basketId, uint256 currentReward, bool cutfee)
    external view returns(uint256, uint256);
  function getReward(address account, uint256[] memory poolId, uint256[] memory basketIds) external view
    returns(uint256[] memory, uint256[] memory);
  function poolInfoLength(uint256 poolId) external view returns(uint256);
  function reInvestInfoLength(uint256 poolId) external view returns(uint256);
}

