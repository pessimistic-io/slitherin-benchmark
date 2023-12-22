// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

interface IGlpRewardRouter {
  function feeGlpTracker() external view returns (address);

  function stakedGlpTracker() external view returns (address);

  function glpManager() external view returns (address);

  function glp() external view returns (address);

  function mintAndStakeGlp(
    address _token,
    uint256 _amount,
    uint256 _minUsdg,
    uint256 _minGlp
  ) external returns (uint256);

  function unstakeAndRedeemGlp(
    address _tokenOut,
    uint256 _glpAmount,
    uint256 _minOut,
    address _receiver
  ) external returns (uint256);

  function mintAndStakeGlpETH(
    uint256 _minUsdg,
    uint256 _minGlp
  ) external payable returns (uint256);

  function compound() external;
}

