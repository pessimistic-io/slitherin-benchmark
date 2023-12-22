// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./IStorageSet.sol";

interface IRouter is IStorageSet{
  struct Liquidity{
    address pool;
    string name;
    string symbol;
    uint8 decimals;
    uint256 balance;
  }
  function isLpToken(address token) external view returns(bool,bool);
  function getLpToken(address collateralToken) external view returns(address);
  function getPoolPrice(address _pool,bool _maximise,bool _includeProfit,bool _includeLoss) external view returns(uint256);

  function addLiquidityNative(
    address _targetPool,
    uint256 _amount, 
    address _to,
    uint256 _price,
    address _referrer,
    bytes[] memory _priceUpdateData
  ) external payable returns(uint256);
  function addLiquidity(
    address _collateralToken,
    address _targetPool,
    uint256 _amount,
    address _to,
    uint256 _price,
    address _referrer,
    bytes[] memory _priceUpdateData
  ) external returns(uint256);
  function removeLiquidity(
    address _collateralToken,
    address _receiveToken,
    uint256 _liquidity,
    address _to,
    uint256 _price,
    address _referrer,
    bytes[] memory _priceUpdateData
  ) external returns(uint256);

  function getPoolLiqFee(address pool) external view returns(uint256);
  function addPlugin(address _plugin) external;
  function removePlugin(address _plugin) external;
  
  function increasePosition(
    address _indexToken,
    address _collateralToken,
    uint256 _amountIn,
    uint256 _sizeDelta,
    uint256 _price,
    bool _isLong,
    address _referrer,
    bytes[] memory _priceUpdateData
  ) external payable;

  function decreasePosition(
    address _indexToken, 
    address _collateralToken, 
    uint256 _sizeDelta, 
    uint256 _collateralDelta, 
    bool _isLong, 
    address _receiver,
    uint256 _price,
    address _referrer,
    bytes[] memory _priceUpdateData
  )external payable returns(uint256);

  function pluginIncreasePosition(
    address _account,
    address _indexToken,
    address _collateralToken,
    uint256 _amountIn,
    uint256 _sizeDelta,
    bool _isLong
  ) external payable;

  function pluginDecreasePosition(
    address _account,
    address _indexToken, 
    address _collateralToken, 
    uint256 _sizeDelta, 
    uint256 _collateralDelta, 
    bool _isLong, 
    address _receiver
  )external payable returns(uint256);

  function liquidatePosition(
    address _account,
    address _indexToken, 
    address _collateralToken, 
    bool _isLong,
    address _feeReceiver,
    bytes[] memory _priceUpdateData
  ) external;
}

