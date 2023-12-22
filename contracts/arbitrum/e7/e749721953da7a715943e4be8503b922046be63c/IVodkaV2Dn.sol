// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IVodkaV2Dn {
  struct PositionInfo {
    uint256 deposit; // total amount of deposit
    uint256 position; // position size original + leverage
    uint256 price; // GMXMarket price
    uint256 closedPositionValue; // value of position when closed
    uint256 closePNL;
    address user; // user that created the position
    uint32 positionId;
    address liquidator; //address of the liquidator
    uint16 leverageMultiplier; // leverage multiplier, 2000 = 2x, 10000 = 10x
    bool closed;
    bool liquidated; // true if position was liquidated
    address longToken;
  }

  struct PositionDebt {
    uint256 longDebtValue;
    uint256 shortDebtValue;
  }

  struct Dtv {
    uint256 currentDTV;
    uint256 currentPosition;
    uint256 currentDebt;
  }

  function getAllUsers() external view returns (address[] memory);

  function getTotalOpenPosition(address _user) external view returns (uint256);

  function getUpdatedDebt(
    uint256 _positionID,
    address _user
  ) external view returns (uint256 currentDTV, uint256 currentDebt, uint256 currentPosition);

  function positionInfo(address _user, uint256 _positionID) external view returns (PositionInfo memory);

  function positionDebt(address _user, uint256 _positionID) external view returns (PositionDebt memory);
}

