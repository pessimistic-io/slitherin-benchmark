// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

struct MintParams {
  address asset; // USDC | BUSD depends at chain
  uint256 amount; // amount asset
  string referral; // code from Referral Program -> if not have -> set empty
}

interface IOvernightExchange {
  function usdPlus() external view returns (address);

  function buyFee() external view returns (uint256);

  function buyFeeDenominator() external view returns (uint256);

  function redeemFee() external view returns (uint256);

  function redeemFeeDenominator() external view returns (uint256);

  function mint(MintParams calldata params) external returns (uint256);

  function redeem(address _asset, uint256 _amount) external returns (uint256);
}

