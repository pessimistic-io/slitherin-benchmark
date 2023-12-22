// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;
import "./Ownable.sol";
import "./Pausable.sol";
import "./IERC20.sol";
import "./IEpochStaking.sol";

contract EpochStakingController is Ownable {
  IEpochStaking[] public contracts;

  function addContract(address _contract) external onlyOwner {
    contracts.push(IEpochStaking(_contract));
  }

  function initAll() external onlyOwner {
    for (uint256 i = 0; i < contracts.length; i++) {
      contracts[i].init();
    }
  }

  function setWhitelist(address _wl) external onlyOwner {
    for (uint256 i = 0; i < contracts.length; i++) {
      contracts[i].setWhitelist(_wl);
    }
  }

  function advanceEpochAll() external onlyOwner {
    for (uint256 i = 0; i < contracts.length; i++) {
      contracts[i].advanceEpoch();
    }
  }

  function pauseAll() external onlyOwner {
    for (uint256 i = 0; i < contracts.length; i++) {
      contracts[i].pause();
    }
  }

  function unpauseAll() external onlyOwner {
    for (uint256 i = 0; i < contracts.length; i++) {
      contracts[i].unpause();
    }
  }
}

