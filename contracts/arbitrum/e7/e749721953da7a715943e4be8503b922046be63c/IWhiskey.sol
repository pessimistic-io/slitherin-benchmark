// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IWhiskey {
  struct UserInfo {
    address user; // user that created the position
    uint256 deposit; // total amount of deposit
    uint256 leverage; // leverage used
    uint256 position; // position size
    uint256 price; // gToken (gDAI) price when position was created
    bool liquidated; // true if position was liquidated
    bool withdrawalRequested; // true if user requested withdrawal
    uint256 epochUnlock; // epoch when user can withdraw
    uint256 closedPositionValue; // value of position when closed
  }

  struct Dtv {
    uint256 currentDTV;
    uint256 currentPosition;
    uint256 currentDebt;
  }

  function getTotalNumbersOfOpenPositionBy(address _user) external view returns (uint256);

  function getUpdatedDebtAndValue(
    uint256 _positionID,
    address _user
  ) external view returns (uint256 currentDTV, uint256 currentPosition, uint256 currentDebt);

  function userInfo(address _user, uint256 _positionID) external view returns (UserInfo memory);
}

