// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

interface IErrors {
  error FAILED(string);
  error UNAUTHORIZED(string);
}

interface ITracker {
  function stakedAmounts(address _account) external view returns (uint);

  function totalSupply() external view returns (uint256);
}

interface IBaseToken is IErrors {
  function inPrivateTransferMode() external view returns (bool);

  function isHandler(address) external view returns (bool);

  event UnsafeTransferAllowed(address _account, bool _isActive);
}

interface IBaseMintableToken is IBaseToken {
  function mint(address _account, uint _amount) external;

  function burn(address _account, uint _amount) external;

  function setMinter(address _minter, bool _isActive) external;

  function isMinter(address) external view returns (bool);

  function setBurner(address _burner, bool _isActive) external;

  function isBurner(address) external view returns (bool);
}

interface IBaseDistributorShared {
  function tokensPerSecond() external view returns (uint128);

  function rewardToken() external view returns (address);
}

interface IBaseDistributor is IBaseDistributorShared, IErrors {
  function pendingRewards() external view returns (uint);

  function distribute() external returns (uint);

  function getRate() external view returns (uint);

  event Distribute(uint amount);
}

interface IRewardDistributor is IBaseDistributor {
  function setTokensPerSecond(uint128 _amount) external;

  event TokensPerSecondChange(uint128 amount);
}

interface IBonusDistributor is IBaseDistributor {
  function setBonusMultiplier(uint128 _bonusMultiplierBasisPoints) external;

  event BonusMultiplierChange(uint128 amount);
}

interface IRewardTracker is IBaseDistributorShared {
  function stakedSynthAmounts(address _account) external view returns (uint);

  function distributor() external view returns (address);

  function depositBalances(address _account, address _depositToken) external view returns (uint);

  function stakedAmounts(address _account) external view returns (uint);

  function updateRewards() external;

  function stake(address _depositToken, uint _amount) external;

  function stakeForAccount(address _fundingAccount, address _account, address _depositToken, uint _amount) external;

  function unstake(address _depositToken, uint _amount) external;

  function unstakeForAccount(address _account, address _depositToken, uint _amount, address _receiver) external;

  function claim(address _receiver) external returns (uint);

  function claimForAccount(address _account, address _receiver) external returns (uint);

  function claimable(address _account) external view returns (uint);

  function averageStakedAmounts(address _account) external view returns (uint);

  function cumulativeRewards(address _account) external view returns (uint);

  event Claim(address receiver, uint amount);
}

interface IVester {
  function claimForAccount(address _account, address _receiver) external returns (uint256);

  function transferredAverageStakedAmounts(address _account) external view returns (uint256);

  function transferredCumulativeRewards(address _account) external view returns (uint256);

  function cumulativeRewardDeductions(address _account) external view returns (uint256);

  function bonusRewards(address _account) external view returns (uint256);

  function transferStakeValues(address _sender, address _receiver) external;

  function setTransferredAverageStakedAmounts(address _account, uint256 _amount) external;

  function setTransferredCumulativeRewards(address _account, uint256 _amount) external;

  function setCumulativeRewardDeductions(address _account, uint256 _amount) external;

  function setBonusRewards(address _account, uint256 _amount) external;

  function getMaxVestableAmount(address _account) external view returns (uint256);

  function getCombinedAverageStakedAmount(address _account) external view returns (uint256);
}

