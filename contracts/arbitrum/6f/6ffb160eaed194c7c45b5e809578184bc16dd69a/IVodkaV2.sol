// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IVodkaV2 {
  struct PositionInfo {
    uint256 deposit; // total amount of deposit
    uint256 position; // position size original + leverage
    uint256 price; // GMXMarket price
    uint256 closedPositionValue; // value of position when closed
    uint256 closePNL;
    uint256 leverageAmount; //borrowed amount
    address user; // user that created the position
    uint32 positionId;
    address liquidator; //address of the liquidator
    uint16 leverageMultiplier; // leverage multiplier, 2000 = 2x, 10000 = 10x
    bool closed;
    bool liquidated; // true if position was liquidated
    address longToken;
  }

  struct Dtv {
    uint256 currentDTV;
    uint256 currentPosition;
    uint256 currentDebt;
  }

  function getTotalOpenPosition(address _user) external view returns (uint256);

  function getCurrentLeverageAmount(uint256 _positionID, address _user) external view returns (uint256, uint256);

  function getUpdatedDebt(
    uint256 _positionID,
    address _user
  ) external view returns (uint256 currentDTV, uint256 currentPosition, uint256 currentDebt);

  function positionInfo(address _user, uint256 _positionID) external view returns (PositionInfo memory);
}

