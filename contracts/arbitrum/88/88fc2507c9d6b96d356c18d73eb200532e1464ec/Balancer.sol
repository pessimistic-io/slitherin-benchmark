//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";
import "./IBalancerVault.sol";
import "./IBalancerHelper.sol";

library Balancer {
  struct BalancerSwapOutParam {
    uint256 amount;
    address assetIn;
    address assetOut;
    address recipient;
    bytes32 poolId;
    uint256 maxAmountIn;
  }

  enum ExitKind { EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, EXACT_BPT_IN_FOR_TOKENS_OUT, BPT_IN_FOR_EXACT_TOKENS_OUT }

  function balancerJoinPool(IBalancerVault balancerVault, address[] memory tokens, uint256[] memory maxAmountsIn, bytes32 poolId) external {
    bytes memory userData = abi.encode(1, maxAmountsIn, 0); // JoinKind: 1
    balancerVault.joinPool(
      poolId,
      address(this),
      address(this),
      IBalancerVault.JoinPoolRequest(tokens, maxAmountsIn, userData, false)
    );
  }

  // balancer exit pool with bptAmountIn
  function balancerExitPool(IBalancerVault balancerVault, address[] memory tokens, uint256[] memory minAmountsOut, bytes32 poolId, uint256 bptAmountIn, uint256 tokenIndex) external {
    balancerVault.exitPool(
      poolId,
      address(this),
      payable(address(this)),
      IBalancerVault.ExitPoolRequest(tokens, minAmountsOut, abi.encode(ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, bptAmountIn, tokenIndex), false)
    );
  }

  // balancer exit pool with custom tokenOut amount
  function balancerCustomExitPool(IBalancerVault balancerVault, address[] memory tokens, uint256[] memory minAmountsOut, bytes32 poolId, uint256[] memory amountsOut, uint256 maxBPTAmountIn) external {
    balancerVault.exitPool(
      poolId,
      address(this),
      payable(address(this)),
      IBalancerVault.ExitPoolRequest(tokens, minAmountsOut, abi.encode(ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT, amountsOut, maxBPTAmountIn), false)
    );
  }

  function balancerQueryExit(IBalancerHelper balancerHelper, address[] memory tokens, uint256[] memory minAmountsOut, bytes32 poolId, uint256 bptAmountIn, uint256 tokenIndex) external returns (uint256) {
    uint256 bptIn;
    uint256[] memory amountsOut;
    (bptIn, amountsOut) = balancerHelper.queryExit(
      poolId,
      address(this),
      payable(address(this)),
      IBalancerVault.ExitPoolRequest(tokens, minAmountsOut, abi.encode(ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, bptAmountIn, tokenIndex), false)
    );
    return amountsOut[tokenIndex];
  }

  function balancerSwapIn(IBalancerVault balancerVault, uint256 amount, address assetIn, address assetOut, address recipient, bytes32 poolId) external returns (uint256) {
    IERC20Upgradeable(assetIn).approve(address(balancerVault), amount);
    bytes memory userData;
    uint256 value = balancerVault.swap(
      IBalancerVault.SingleSwap(poolId, IBalancerVault.SwapKind.GIVEN_IN, assetIn, assetOut, amount, userData),
      IBalancerVault.FundManagement(address(this), true, payable(recipient), false),
      0,
      2**256 - 1
    );
    return value;
  }

  function balancerSwapOut(IBalancerVault balancerVault, BalancerSwapOutParam memory param) internal returns (uint256) {
    IERC20Upgradeable(param.assetIn).approve(address(balancerVault), param.maxAmountIn);
    return balancerVault.swap(
      IBalancerVault.SingleSwap(param.poolId, IBalancerVault.SwapKind.GIVEN_OUT, param.assetIn, param.assetOut, param.amount, ""),
      IBalancerVault.FundManagement(address(this), true, payable(param.recipient), false),
      param.maxAmountIn,
      2**256 - 1
    );
  }
}

