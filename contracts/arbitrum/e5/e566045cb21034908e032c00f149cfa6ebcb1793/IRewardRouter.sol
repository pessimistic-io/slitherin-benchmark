// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

/**
 * @title IRewardRouter
 * @author Buooy
 * @notice Defines the basic interface for a GMX Reward Pool.
 **/
interface IRewardRouter {
  event StakeGlp(address account, uint256 amount);
  event UnstakeGlp(address account, uint256 amount);

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

  function unstakeAndRedeemGlpETH(
    uint256 _glpAmount,
    uint256 _minOut,
    address _receiver
  ) external returns (uint256);

  function handleRewards(
    bool _shouldClaimGmx,
    bool _shouldStakeGmx,
    bool _shouldClaimEsGmx,
    bool _shouldStakeEsGmx,
    bool _shouldStakeMultiplierPoints,
    bool _shouldClaimWeth,
    bool _shouldConvertWethToEth
  ) external;

  function compound() external;

  function feeGlpTracker() external view returns (address);
  function stakedGlpTracker() external view returns (address);
}
