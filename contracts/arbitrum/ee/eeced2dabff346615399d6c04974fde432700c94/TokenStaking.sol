// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./POTATO.sol";
import "./IERC721.sol";
import "./ReentrancyGuard.sol";

contract TokenStaking is ReentrancyGuard, Ownable {

  POTATO public token;

  uint256 public constant ONE_YEAR_IN_SECONDS = 31536000;
  uint256 public rewardRate = 1024; // X% APR
  uint256 public immutable decimals;

  mapping(address => staker) public _stakes;

  error ZeroAmount();
  error ZeroAddress();

  struct staker {
    uint256 balance;
    uint256 rewardsEarned;
    uint256 rewardsPaid;
    uint32 updatedAt;
  }

  event Staked(address staker, uint256 amount);
  event Withdraw(address staker, uint256 amount);
  event RewardsPaid(address staker, uint256 amount);


    constructor(POTATO _token) {
        token = _token;
        decimals = IERC20Metadata(token).decimals();
    }

    function stake(uint256 _amount) external nonReentrant {
    updateReward(msg.sender);
    if(_amount == 0) revert ZeroAmount();
    staker storage user = _stakes[msg.sender];
    token.transferFrom(msg.sender, address(this), _amount);
    user.balance += _amount;
    emit Staked(msg.sender, _amount);
    }

    function unstake(uint256 _amount) external nonReentrant {
    updateReward(msg.sender);
    if(_amount == 0) revert ZeroAmount();
    staker storage user = _stakes[msg.sender];
    user.balance -= _amount;
    token.transfer(msg.sender, _amount);
    emit Withdraw(msg.sender, _amount);
    }
    /** 
     @dev note @param rewards are set by default to 1 rewards per year, 3.154e7 is how many seconds it takes to complete a year
     */

    function claim() public nonReentrant {
    staker storage user = _stakes[msg.sender];
    if (user.rewardsEarned > 0) {
      user.rewardsPaid = user.rewardsEarned;
      token.transfer(
        msg.sender,
        user.rewardsEarned
      );
      user.updatedAt = uint32(block.timestamp);
      emit RewardsPaid(msg.sender, user.rewardsPaid);
    }
    }

    function updateRewardRate(uint256 _newRate) external onlyOwner {
        rewardRate = _newRate;
    }

    function changeStakingToken(POTATO _newToken) external onlyOwner {
        token = _newToken;
    }

    function earned(address _staker) public view returns(uint256) {
    if(_staker == address(0)) revert ZeroAddress();
    staker memory user = _stakes[_staker];
    uint256 balance = (user.balance * 10 ** decimals) /
      10 ** decimals;
    if (user.updatedAt <= 0) return 0;
    return
      user.rewardsEarned +
      ((((balance * (uint32(block.timestamp) - user.updatedAt)) /
        ONE_YEAR_IN_SECONDS) * rewardRate) / 100);
    }

    function updateReward(address _staker) private {
    if (_staker != address(0)) {
      staker storage user = _stakes[_staker];
      user.rewardsEarned = earned(_staker);
      user.updatedAt = uint32(block.timestamp);
    }
  }
}
