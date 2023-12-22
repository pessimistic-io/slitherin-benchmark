// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IRum {
  struct PositionInfo {
    uint256 deposit; // total amount of deposit
    uint256 position; // position size
    uint256 buyInPrice; // hlp buy in price
    uint256 leverageAmount;
    uint256 debtAdjustmentValue;
    address liquidator; //address of the liquidator
    address user; // user that created the position
    uint32 positionId;
    uint16 leverageMultiplier; // leverage used
    bool isLiquidated; // true if position was liquidated
    bool isClosed;
  }

  struct Dtv {
    uint256 currentDTV;
    uint256 currentPosition;
    uint256 currentDebt;
    uint256 leverageAmountWithDA;
  }

  function getNumbersOfPosition(address _user) external view returns (uint256);

  function getPosition(
    uint256 _positionID,
    address _user,
    uint256 hlpPrice
  ) external view returns (uint256, uint256, uint256, uint256, uint256);

  function getHLPPrice(bool _maximise) external view returns (uint256);

  function positionInfo(address _user, uint256 _positionID) external view returns (PositionInfo memory);
}

