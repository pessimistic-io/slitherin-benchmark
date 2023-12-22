// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IGLPRouter{
  function unstakeAndRedeemGlp(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external returns (uint256) ;
  function mintAndStakeGlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external  returns (uint256);
}
