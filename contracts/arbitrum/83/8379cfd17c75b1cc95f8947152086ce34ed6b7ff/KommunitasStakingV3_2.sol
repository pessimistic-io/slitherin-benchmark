// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./KommunitasStakingV3_1.sol";

contract KommunitasStakingV3_2 is KommunitasStakingV3_1 {
  address public dev;

  function onlyEligible() internal view virtual {
    require(_msgSender() == dev || _msgSender() == savior || _msgSender() == owner(), '!dev');
  }

  function setDev(address _dev) external virtual onlyOwner {
    require(_dev != dev, 'invalid');
    dev = _dev;
  }

  function togglePause() external virtual override {
    onlyEligible();
    if (paused()) {
      _unpause();
    } else {
      _pause();
    }
  }

  function toggleUnstakePause() external virtual override {
    onlyEligible();
    isUnstakePaused = !isUnstakePaused;
  }
}

