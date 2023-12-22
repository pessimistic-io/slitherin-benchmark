// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./IMintableERC20.sol";
import "./IWithdrawable.sol";
import "./IStorageSet.sol";
import "./ILP.sol";

interface IMixedLP is ILP,IMintableERC20,IWithdrawable,IStorageSet{
  function isWhitelistedToken(address _token) external view returns (bool);
  function allTokensLength() external view returns(uint256);
  function allTokens(uint256 i) external view returns(address);
  function isTokenPooled(address _token) external view returns(bool);
  function tokenReserves(address _token) external view returns(uint256);

  function setTokenConfigs(address[] memory _tokens, bool[] memory _isWhitelisteds) external;

  function getAum(bool maximise) external view returns (uint256);
  function getSupplyWithPnl(bool _includeProfit, bool _includeLoss) external view returns(uint256);
  function getPrice(bool _maximise,bool _includeProfit, bool _includeLoss) external view returns(uint256);

  function transferIn(address _token, uint256 _amount) external;
  function updateTokenReserves(address _token) external;
}

