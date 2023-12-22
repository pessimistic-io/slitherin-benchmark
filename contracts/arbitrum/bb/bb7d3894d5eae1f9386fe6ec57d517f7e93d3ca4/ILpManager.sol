// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./IStorageSet.sol";

interface ILpManager is IStorageSet{
  function isLpToken(address _lpToken) external view returns(bool);
  function lpEnable(address _lpToken) external view returns(bool);

  function getAccountPoolLength(address _account) external view returns(uint256);
  function getAccountPoolAt(address _account, uint256 _index) external view returns(address);

  function getPoolPrice(address _pool, bool _maximise,bool _includeProfit, bool _includeLoss) external view returns(uint256);
  function lpTokens(address collateralToken) external view returns(address);
  function getSupplyWithPnl(address _lpToken, bool _includeProfit, bool _includeLoss) external view returns(uint256);

  function addLiquidityNative(address _to,address _targetPool) external returns(uint256);
  function addLiquidity(address _collateralToken,address _targetPool,address _to) external returns(uint256);
  function removeLiquidity(address _pool,address _receiveToken, address _to) external returns(uint256);

  function setPoolActive(address _pool, bool _isLp, bool _active) external;
}
