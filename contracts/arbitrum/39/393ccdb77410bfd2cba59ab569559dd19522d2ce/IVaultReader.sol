// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IVaultReader {
  function getVaultTokenInfoV3(address _vault, address _positionManager, address _weth, uint256 _usdgAmount, address[] memory _tokens) external view returns (uint256[] memory);
}
