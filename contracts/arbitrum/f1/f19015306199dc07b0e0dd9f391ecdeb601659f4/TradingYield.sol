// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./TransferHelper.sol";
import "./IHandler.sol";
import "./IDipxStorage.sol";
import "./IYield.sol";
import "./IRewardDistributor.sol";
import "./EnumerableSet.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";

contract TradingYield is IYield,Initializable,OwnableUpgradeable,ReentrancyGuardUpgradeable{
  using EnumerableSet for EnumerableSet.AddressSet;
  
  struct Reward{
    address pool;
    uint256 date;
    uint256 tokensPerInterval;
  }

  uint256 public constant BASIS_POINT_DIVISOR = 100000000;
  uint256 public constant PRECISION = 1e18;
  uint256 constant SECONDS_PER_DAY = 24 * 60 * 60;
  int256 constant OFFSET19700101 = 2440588;

  address public distributor;
  address public dipxStorage;
  uint256 public startAt;
  
  address public rewardPool;
  Reward[] public historyRewards;
  mapping(address => uint256) public previousClaimTimes;
  mapping(address => uint256) public cumulativeRewards;

  event Claim(address account, address token, uint256 amount);
  function initialize(
    address _distributor,
    address _storage, 
    address _rewardPool
  ) public initializer {
    __Ownable_init();
    __ReentrancyGuard_init();
    distributor = _distributor;
    dipxStorage = _storage;
    rewardPool = _rewardPool;
    startAt = block.timestamp;
  }

  function setStartAt(uint256 ts) external onlyOwner{
    startAt = ts;
  }

  function setStorage(address _storage) external onlyOwner{
    dipxStorage = _storage;
  }

  function updateRewards() external override nonReentrant {
    _updateRewards();
  }

  function _updateRewards() private{
    IRewardDistributor(distributor).distribute();

    uint256 tokensPerInterval = IRewardDistributor(distributor).yieldTokensPerInterval(address(this));
    uint256 date = timestampToDateNumber(block.timestamp);
    if(historyRewards.length == 0){
      Reward memory reward = Reward(rewardPool,date, tokensPerInterval);
      historyRewards.push(reward);
    }else{
      Reward storage reward = historyRewards[historyRewards.length - 1];
      if(reward.date == date){
        reward.tokensPerInterval = tokensPerInterval;
      }else{
        historyRewards.push(Reward(rewardPool, date, tokensPerInterval));
      }
    }
  }

  function getRewardByDate(uint256 _date) public view returns(uint256){
    uint256 reward;
    for (uint256 i = 0; i < historyRewards.length; i++) {
      if(historyRewards[i].date <= _date){
        reward = historyRewards[i].tokensPerInterval * SECONDS_PER_DAY;
      }else{
        break;
      }
    }
    return reward;
  }

  function timestampToDate(uint256 timestamp) internal pure returns (uint256 year, uint256 month, uint256 day) {
    unchecked {
      (year, month, day) = _daysToDate(timestamp / SECONDS_PER_DAY);
    }
  }
  function timestampToDateNumber(uint256 timestamp) internal pure returns(uint256 date){
    (uint256 year,uint256 month,uint256 day) = timestampToDate(timestamp);
    return year*10000 + month*100 + day;
  }
  function _daysToDate(uint256 _days) internal pure returns (uint256 year, uint256 month, uint256 day) {
    unchecked {
      int256 __days = int256(_days);

      int256 L = __days + 68569 + OFFSET19700101;
      int256 N = (4 * L) / 146097;
      L = L - (146097 * N + 3) / 4;
      int256 _year = (4000 * (L + 1)) / 1461001;
      L = L - (1461 * _year) / 4 + 31;
      int256 _month = (80 * L) / 2447;
      int256 _day = L - (2447 * _month) / 80;
      L = _month / 11;
      _month = _month + 2 - 12 * L;
      _year = 100 * (N - 49) + _year + L;

      year = uint256(_year);
      month = uint256(_month);
      day = uint256(_day);
    }
  }

  function calculateClaimableReward(address _account) public view returns(uint256){
    uint256 preClaimAt = previousClaimTimes[_account];
    uint256 rewardEndAt = block.timestamp;

    if(preClaimAt < startAt){
      preClaimAt = startAt;
    }

    if(timestampToDateNumber(preClaimAt) == timestampToDateNumber(rewardEndAt)){
      return 0;
    }
    
    uint256 claimableReward;
    address handler = IDipxStorage(dipxStorage).handler();
    for (uint256 ts = preClaimAt; ts < rewardEndAt; ts=ts+24*60*60) {
      uint256 date = timestampToDateNumber(ts);
      bytes32 key = keccak256(abi.encodePacked(_account,date,rewardPool));
      IHandler.PoolVolume memory userVolume = IHandler(handler).getUserVolume(key);
      if(userVolume.value > 0){
        IHandler.PoolVolume memory poolVolume = IHandler(handler).getPoolVolume(rewardPool, date);
        uint256 reward = getRewardByDate(date);
        claimableReward = userVolume.value * reward / poolVolume.value;
      }
    }

    return claimableReward;
  }

  function claim() external nonReentrant{
    _updateRewards();
    address account = msg.sender;
    uint256 claimableReward = calculateClaimableReward(account);
    require(claimableReward > 0, "No reward");

    previousClaimTimes[account] = block.timestamp;
    cumulativeRewards[account] = cumulativeRewards[account] + claimableReward;
    address rewardToken = IRewardDistributor(distributor).rewardToken();
    TransferHelper.safeTransfer(rewardToken, msg.sender, claimableReward);

    emit Claim(account, rewardToken, claimableReward);
  }
}
