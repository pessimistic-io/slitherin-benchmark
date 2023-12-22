// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ILevelARBLongSLLPReader {
  function svTokenValue() external view returns (uint256);
  function assetValue() external view returns (uint256);
  function assetValueWithPrice(uint256 _sllpPrice) external view returns (uint256);
  function debtValue() external view returns (uint256);
  function equityValue() external view returns (uint256);
  function assetAmt() external view returns (address[4] memory, uint256[4] memory);
  function debtAmt() external view returns (uint256, uint256);
  function lpAmt() external view returns (uint256);
  function leverage() external view returns (uint256);
  function debtRatio() external view returns (uint256);
  function tokenValue(address _token, uint256 _amt) external view returns (uint256);
  function sllpPrice(bool _bool) external view returns (uint256);
  // TODO To use currentTokenWeight instead of target
  function currentTokenWeight(address _token) external view returns (uint256);
  function currentTokenWeights() external view returns (address[4] memory, uint256[4] memory);
  function additionalCapacity() external view returns (uint256);
  function capacity() external view returns (uint256);
}

