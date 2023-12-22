// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IMaotai {
  struct UserInfo {
    address user;
    uint256 deposit;
    uint256 leverage;
    uint256 position;
    uint256 price;
    bool liquidated;
    uint256 closedPositionValue;
    address liquidator;
    uint256 closePNL;
    uint256 leverageAmount;
    uint256 positionId;
    bool closed;
  }

  struct Dtv {
    uint256 currentDTV;
    uint256 currentPosition;
    uint256 currentDebt;
  }

  function getTotalNumbersOfOpenPosition(address _user) external view returns (uint256);

  function getUpdatedDebt(
    uint256 _positionID,
    address _user
  ) external view returns (uint256 currentDTV, uint256 currentPosition, uint256 currentDebt);

  function userInfo(address _user, uint256 _positionID) external view returns (UserInfo memory);
}

