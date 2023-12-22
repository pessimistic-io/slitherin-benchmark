// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "./Ownable.sol";
import "./ILendingRewards.sol";

contract RewardsLocker is Ownable {
  ILendingRewards public rewards;

  constructor(ILendingRewards _rewards) {
    rewards = _rewards;
  }

  function withdrawRewards() external {
    rewards.claimReward();
    uint256 _bal = address(this).balance;
    require(_bal > 0, 'WITHDRAW: no rewards to withdraw');
    (bool success, ) = payable(owner()).call{ value: _bal }('');
    require(success, 'WITHDRAW: ETH not sent to owner');
  }

  receive() external payable {}
}

