// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;
pragma abicoder v2;

struct MintParams {
  address asset; // USDC | BUSD depends at chain
  uint256 amount; // amount asset
  string referral; // code from Referral Program -> if not have -> set empty
}

interface IOvernightExchange {
  function usdPlus() external view returns (address);

  function mint(MintParams calldata params) external returns (uint256);

  function redeem(address _asset, uint256 _amount) external returns (uint256);
}

