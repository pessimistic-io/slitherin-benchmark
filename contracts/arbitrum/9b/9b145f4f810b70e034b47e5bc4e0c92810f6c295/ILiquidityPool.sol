// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;


interface ILiquidityPool {

  struct AssetInfo {
    /// @notice amount of token deposited (via add liquidity or increase long position)
    uint256 poolAmount;
    /// @notice amount of token reserved for paying out when user decrease long position
    uint256 reservedAmount;
    /// @notice total borrowed (in USD) to leverage
    uint256 guaranteedValue;
    /// @notice total size of all short positions
    uint256 totalShortSize;
  }

  function calcRemoveLiquidity(
    address _tranche,
    address _tokenOut,
    uint256 _lpAmt
  ) external view returns (
    uint256 outAmount,
    uint256 outAmountAfterFee,
    uint256 fee
  );
  function calcSwapOutput(
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn
  ) external view returns (
    uint256 amountOut,
    uint256 feeAmount
  );
  function fee() external view returns (
    uint256 positionFee,
    uint256 liquidationFee,
    uint256 baseSwapFee,
    uint256 taxBasisPoint,
    uint256 stableCoinBaseSwapFee,
    uint256 stableCoinTaxBasisPoint,
    uint256 daoFee
  );
  function isAsset(address _asset) external view returns (bool isAsset);
  function targetWeights(address _token) external view returns (uint256 weight);
  function totalWeight() external view returns (uint256 totalWeight);
  function getPoolValue(bool _bool) external view returns (uint256 value);
  function getTrancheValue(
    address _tranche,
    bool _max
  ) external view returns (uint256 sum);

  function addRemoveLiquidityFee() external view returns (uint256);
  function virtualPoolValue() external view returns (uint256);
  function getPoolAsset(address _token) external view returns (AssetInfo memory);
  function trancheAssets(address _tranche, address _token) external view returns (
    uint256 poolAmount,
    uint256 reservedAmount,
    uint256 guaranteedValue,
    uint256 totalShortSize
  );
}

