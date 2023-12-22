// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;


interface ILiquidityCalculator {
  function calcAddRemoveLiquidityFee(address _token, uint256 _tokenPrice, uint256 _valueChange, bool _isAdd) external view returns (uint256);


}

