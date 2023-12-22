// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICamelotReader {
  function leverage() external view returns (uint256);
  function delta() external view returns (int256);
  function debtRatio() external view returns (uint256);
  function assetValue() external view returns (uint256);
  function debtValue() external view returns (uint256, uint256);
  function equityValue(bool _addProtocolFees) external view returns (uint256);
  function assetAmt() external view returns (uint256, uint256);
  function debtAmt() external view returns (uint256, uint256);
  function lpAmt() external view returns (uint256);
  function lpAmtWithMultiplier() external view returns (uint256);
  function tokenValue(address _token, uint256 _amt) external view returns (uint256);
  function additionalCapacity() external view returns (uint256);
  function capacity() external view returns (uint256);
}

