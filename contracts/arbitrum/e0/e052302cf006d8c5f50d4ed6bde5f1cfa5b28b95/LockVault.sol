// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./IERC20.sol";
import "./SafeERC20.sol";

interface INativeFarm {
    // Deposit LP tokens to the farm for farm's token allocation.
    function deposit(uint256 _pid, uint256 _amount) external;
    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external;
    // Get pool info
    function poolInfo(uint256 index) external view returns (address, uint256, uint256, uint256);
    // cake
    function cake() external view returns (address);
    function totalAllocPoint() external view returns (uint256);
    function cakePerSecond() external view returns (uint256);
}

contract LockVault {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  address public lpAddress; 
  address public nativeFarm; 
  address public fish; 
  uint256 public pid; 
  address public constant rewardVault = 0x3Efa7cE8caE7341283c148389A08ABB3522B2abE;

  constructor(
    address _nativeFarm,
    uint256 _pid
  ) public {
    nativeFarm = _nativeFarm;
    pid = _pid;

    // load lpAddress
    (lpAddress,,,) = INativeFarm(_nativeFarm).poolInfo(_pid);
    // load Fish address
    fish = INativeFarm(_nativeFarm).cake();
    // Infinite approve
    IERC20(lpAddress).safeApprove(_nativeFarm, uint256(-1));
  }

  function deposit() external {
    uint256 bal = IERC20(lpAddress).balanceOf(msg.sender);
    IERC20(lpAddress).transferFrom(msg.sender, address(this), bal);

    INativeFarm(nativeFarm).deposit(pid, bal);
  }

  function harvest() external {
    INativeFarm(nativeFarm).withdraw(pid, 0);

    uint256 bal = IERC20(fish).balanceOf(address(this));
    IERC20(fish).transfer(rewardVault, bal);
  }
}
