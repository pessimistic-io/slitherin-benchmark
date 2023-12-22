// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

interface IVaultPriceFeed {
  function chainlinkPriceFeed() external view returns(address);
  function pythPriceFeed() external view returns(address);
  function eth() external view returns(address);
  function btc() external view returns(address);
  function decimals() external view returns(uint8);
  function getPrice(address _token, bool _maximise) external view returns (uint256);
  function setPythEnabled(bool _isEnabled) external;
  function setAmmEnabled(bool _isEnabled) external;
  function setTokens(address _btc, address _eth) external;
}
