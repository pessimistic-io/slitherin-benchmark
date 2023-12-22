// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IVault {
  struct UserInfo {
    // common
    address user; // maotai, rum, sake, sakeV1, vodka, vodkaV2, whiskey
    uint256 deposit; // maotai, rum, sake, sakeV1, vodka, vodkaV2, whiskey
    uint256 position; // maotai, rum, sake, sakeV1, vodka, vodkaV2, whiskey
    // leverage related
    uint256 leverage; // maotai, sake, sakeV1, vodka, whiskey
    uint256 leverageMultiplier; // rum, vodkaV2
    uint256 leverageAmount; // maotai, rum, sake, vodka, vodkaV2
    // price
    uint256 buyInPrice; // rum
    uint256 price; // maotai, sake, sakeV1, vodka, vodkaV2, whiskey
    // liquidation
    bool liquidated; // maotai, sake, sakeV1, vodka, vodkaV2, whiskey
    address liquidator; // maotai, rum, sake, sakeV1, vodka, vodkaV2
    // position
    uint256 positionId; // maotai, rum, sake, vodka, vodkaV2
    uint256 closedPositionValue; // maotai, sake, sakeV1, vodka, vodkaV2, whiskey
    uint256 closePNL; // maotai, sake, sakeV1, vodka, vodkaV2
    bool closed; // maotai, sake, vodkaV2
    bool isClosed; // rum, vodka
    bool isLiquidated; // rum
    // others
    uint256 cooldownPeriodElapse; // sake, sakeV1
    uint256 debtAdjustmentValue; // rum
    uint256 epochUnlock; // whiskey
    address longToken; // vodkaV2
    bool withdrawalRequested; // whiskey
  }

  struct Dtv {
    uint256 currentDTV;
    uint256 currentPosition;
    uint256 currentDebt;
    uint256 leverageAmountWithDA;
  }

  function getTotalNumbersOfOpenPositionBy(address _user) external view returns (uint256);

  function getUpdatedDebt(
    uint256 _positionID,
    address _user
  ) external view returns (uint256 currentDTV, uint256 currentPosition, uint256 currentDebt);

  function userInfo(address _user, uint256 _positionID) external view returns (UserInfo memory);
}

