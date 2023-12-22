// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./KommunitasStakingV3.sol";

contract KommunitasStakingV3_1 is KommunitasStakingV3 {
  bool public isUnstakePaused;

  function unstake(
    uint232 _userStakedIndex,
    uint256 _amount,
    address _staker
  ) public virtual override{
    require(!isUnstakePaused, "paused");
    super.unstake(_userStakedIndex, _amount, _staker);
  }

  function toggleUnstakePause() external virtual onlyOwner {
    isUnstakePaused = !isUnstakePaused;
  }

}
