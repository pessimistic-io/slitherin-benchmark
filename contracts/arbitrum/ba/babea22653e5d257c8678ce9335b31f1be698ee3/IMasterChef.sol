// SPDX-License-Identifier: GPL-3.0

import "./IOREO.sol";

pragma solidity 0.6.12;

interface IMasterChef {
  /// @dev functions return information. no states changed.
  function poolLength() external view returns (uint256);

  function pendingOreo(address _stakeToken, address _user) external view returns (uint256);

  function userInfo(address _stakeToken, address _user)
    external
    view
    returns (
      uint256,
      uint256,
      address
    );

  function poolInfo(address _stakeToken)
    external
    view
    returns (
      uint256,
      uint256,
      uint256,
      uint256
    );

  function devAddr() external view returns (address);

  function refAddr() external view returns (address);

  function bonusMultiplier() external view returns (uint256);

  function totalAllocPoint() external view returns (uint256);

  function oreoPerBlock() external view returns (uint256);

  /// @dev configuration functions
  function addPool(
    address _stakeToken,
    uint256 _allocPoint,
    uint256 _depositFee
  ) external;

  function setPool(
    address _stakeToken,
    uint256 _allocPoint,
    uint256 _depositFee
  ) external;

  function updatePool(address _stakeToken) external;

  function removePool(address _stakeToken) external;

  /// @dev user interaction functions
  function deposit(
    address _for,
    address _stakeToken,
    uint256 _amount
  ) external;

  function withdraw(
    address _for,
    address _stakeToken,
    uint256 _amount
  ) external;

  function depositOreo(address _for, uint256 _amount) external;

  function withdrawOreo(address _for, uint256 _amount) external;

  function harvest(address _for, address _stakeToken) external;

  function harvest(address _for, address[] calldata _stakeToken) external;

  function emergencyWithdraw(address _for, address _stakeToken) external;

  function mintExtraReward(
    address _stakeToken,
    address _to,
    uint256 _amount
  ) external;

  function oreo() external returns (IOREO);
}

