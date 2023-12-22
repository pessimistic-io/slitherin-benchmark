// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IVodkaV1a {
  struct UserInfo {
    address user; // user that created the position
    uint256 deposit; // total amount of deposit
    uint256 leverage; // leverage used
    uint256 position; // position size
    uint256 price; // glp price
    bool liquidated; // true if position was liquidated
    uint256 closedPositionValue; // value of position when closed
    address liquidator; //address of the liquidator
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

  function getTotalNumbersOfOpenPositionBy(address _user) external view returns (uint256);

  function getUpdatedDebt(
    uint256 _positionID,
    address _user
  ) external view returns (uint256 currentDTV, uint256 currentPosition, uint256 currentDebt);

  function userInfo(address _user, uint256 _positionID) external view returns (UserInfo memory);
}

