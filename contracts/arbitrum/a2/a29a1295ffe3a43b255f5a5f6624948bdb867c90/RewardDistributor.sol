// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IERC20.sol";
import "./EnumerableSet.sol";
import "./IYield.sol";
import "./IRewardDistributor.sol";
import "./TransferHelper.sol";

contract RewardDistributor is IRewardDistributor,ReentrancyGuardUpgradeable,OwnableUpgradeable{
  using EnumerableSet for EnumerableSet.AddressSet;

  address public override rewardToken;
  EnumerableSet.AddressSet private yieldTrackers;

  mapping(address => uint256) public override yieldTokensPerInterval;
  mapping(address => uint256) public override yieldLastDistributionTime;
  mapping(address => uint256) public cumulativeRewards;

  event Distribute(address yield,uint256 amount);
  event TokensPerIntervalChange(address yield, uint256 amount);

  function initialize(address _rewardToken) initializer public {
    __Ownable_init();
    __ReentrancyGuard_init();
    rewardToken = _rewardToken;
  }

  function setRewardToken(address _rewardToken) external onlyOwner{
    rewardToken = _rewardToken;
  }
  function setTracker(address _tracker, bool _active) external onlyOwner{
    if(_active){
      yieldTrackers.add(_tracker);
    }else{
      yieldTrackers.remove(_tracker);
    }
  }
  function setYieldLastDistributeAt(address _tracker, uint256 _ts) external onlyOwner{
    yieldLastDistributionTime[_tracker] = _ts;
  }
  function yieldTrackersLength() public view returns(uint256){
    return yieldTrackers.length();
  }
  function yieldTrackerAt(uint256 _index) public view returns(address){
    return yieldTrackers.at(_index);
  }
  function isYieldTracker(address _yield) public view returns(bool){
    return yieldTrackers.contains(_yield);
  }

  function setTokensPerInterval(address _yield, uint256 _amount) external onlyOwner {
    IYield(_yield).updateRewards();
    yieldTokensPerInterval[_yield] = _amount;
    emit TokensPerIntervalChange(_yield,_amount);
  }

  function pendingRewards(address _yield) public override view returns (uint256) {
    if (block.timestamp == yieldLastDistributionTime[_yield]) {
      return 0;
    }

    uint256 timeDiff = block.timestamp - yieldLastDistributionTime[_yield];
    return yieldTokensPerInterval[_yield] * timeDiff;
  }

  function distribute() external override returns (uint256) {
    require(isYieldTracker(msg.sender), "RewardDistributor: invalid msg.sender");
    uint256 amount = pendingRewards(msg.sender);
    if (amount == 0) { return 0; }

    yieldLastDistributionTime[msg.sender] = block.timestamp;

    uint256 balance = IERC20(rewardToken).balanceOf(address(this));
    if (amount > balance) { amount = balance; }

    TransferHelper.safeTransfer(rewardToken, msg.sender, amount);

    cumulativeRewards[msg.sender] = cumulativeRewards[msg.sender] + amount;

    emit Distribute(msg.sender,amount);
    return amount;
  }
}
