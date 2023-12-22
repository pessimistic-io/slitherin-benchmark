// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

interface IHandler{
  struct PoolVolume {
    address pool;
    uint256 date;
    uint256 value;
    uint256 valueInUsd;
    uint256 fee;
    uint256 feeInUsd;
    uint256 realValue;
    uint256 realValueInUsd;
    uint256 rebateFee;
    uint256 rebateFeeInUsd;
  }
  struct PoolLiquidity {
    address pool;
    uint256 date;
    uint256 totalSupply;
    uint256 aum;
    uint256 price;
    uint256 supplyWithPnl;
  }  

  function getPoolVolume(address pool, uint256 date) external view returns(PoolVolume memory);
  function getUserVolume(bytes32 key) external view returns(PoolVolume memory);

  function beforeAddLiquidity(address collateralToken,address targetPool,address to) external;
  function afterAddLiquidity(address collateralToken,address targetPool,address to) external;
  function beforeRemoveLiquidity(address pool,address receiveToken, address to) external;
  function afterRemoveLiquidity(address pool,address receiveToken, address to) external;

  function beforeIncreasePosition(
    address account,
    address indexToken, 
    address collateralToken,
    uint256 sizeDelta,
    uint256 collateralDelta,
    bool isLong
  ) external;
  function afterIncreasePosition(
    address account,
    address indexToken, 
    address collateralToken,
    uint256 sizeDelta,
    uint256 collateralDelta,
    bool isLong,
    uint256 price,
    uint256 fee
  ) external;
  function beforeDecreasePosition(
    address account,
    address indexToken, 
    address collateralToken, 
    uint256 sizeDelta, 
    uint256 collateralDelta, 
    bool isLong, 
    address receiver
  ) external;
  function afterDecreasePosition(
    address account,
    address indexToken, 
    address collateralToken, 
    uint256 sizeDelta, 
    uint256 collateralDelta, 
    bool isLong, 
    address receiver,
    uint256 fee
  ) external;
  function beforeLiquidatePosition(
    address account, 
    address indexToken, 
    address collateralToken, 
    bool isLong,
    address feeReceiver
  ) external;
  function afterLiquidatePosition(
    address account, 
    address indexToken, 
    address collateralToken, 
    bool isLong,
    address feeReceiver,
    uint256 size, 
    uint256 collateral, 
    uint256 markPrice, 
    uint256 liqFee,
    uint256 marginFee
  ) external;

  function afterRebate(address token, address account, uint256 amount) external;
}

