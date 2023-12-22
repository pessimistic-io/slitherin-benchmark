// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IReferralStorage {
  /*==================================================== EVENTS ===========================================================*/

  event Reward(address referrer, address player, address token, uint256 amount);
  event RewardRemoved(address referrer, address player, address token, uint256 amount);

  function setReward(address _player, address _token, uint256 _amount) external returns (uint256 _reward);
  function removeReward(address _player, address _token, uint256 _amount) external; 
}

