// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IGMXVaultEvents {

  /* ======================== EVENTS ========================= */

  event FeeMinted(uint256 fee);
  event KeeperUpdated(address keeper, bool approval);
  event TreasuryUpdated(address treasury);
  event SwapRouterUpdated(address router);
  event RewardTokenUpdated(address rewardToken);
  event CallbackUpdated(address callback);
  event FeePerSecondUpdated(uint256 feePerSecond);
  event ParameterLimitsUpdated(
    uint256 debtRatioStepThreshold,
    uint256 debtRatioUpperLimit,
    uint256 debtRatioLowerLimit,
    int256 deltaUpperLimit,
    int256 deltaLowerLimit
  );
  event MinVaultSlippageUpdated(uint256 minVaultSlippage);
  event LiquiditySlippageUpdated(uint256 liquiditySlippage);
  event SwapSlippageUpdated(uint256 swapSlippage);
  event CallbackGasLimitUpdated(uint256 callbackGasLimit);
  event GMXExchangeRouterUpdated(address addr);
  event GMXRouterUpdated(address addr);
  event GMXDepositVaultUpdated(address addr);
  event GMXWithdrawalVaultUpdated(address addr);
  event GMXRoleStoreUpdated(address addr);
  event MinAssetValueUpdated(uint256 value);
  event MaxAssetValueUpdated(uint256 value);

  event DepositCreated(
    address indexed user,
    address asset,
    uint256 assetAmt
  );
  event DepositCompleted(
    address indexed user,
    uint256 shareAmt,
    uint256 equityBefore,
    uint256 equityAfter
  );
  event DepositCancelled(
    address indexed user
  );
  event DepositFailed(bytes reason);
  event DepositFailureProcessed();
  event DepositFailureLiquidityWithdrawalProcessed();

  event WithdrawCreated(address indexed user, uint256 shareAmt);
  event WithdrawCompleted(
    address indexed user,
    address token,
    uint256 tokenAmt
  );
  event WithdrawCancelled(address indexed user);
  event WithdrawFailed(bytes reason);
  event WithdrawFailureProcessed();
  event WithdrawFailureLiquidityAddedProcessed();

  event BorrowSuccess(uint256 borrowTokenAAmt, uint256 borrowTokenBAmt);
  event RepaySuccess(uint256 repayTokenAAmt, uint256 repayTokenBAmt);

  event RebalanceAdd(
    uint rebalanceType,
    uint256 borrowTokenAAmt,
    uint256 borrowTokenBAmt
  );
  event RebalanceAddProcessed();
  event RebalanceRemove(
    uint rebalanceType,
    uint256 lpAmtToRemove
  );
  event RebalanceRemoveProcessed();
  event RebalanceSuccess(
    uint256 svTokenValueBefore,
    uint256 svTokenValueAfter
  );
  event RebalanceOpen(
    bytes reason,
    uint256 svTokenValueBefore,
    uint256 svTokenValueAfter
  );
  event RebalanceCancelled();

  event CompoundCompleted();
  event CompoundCancelled();

  event LiquidityAdded(uint256 tokenAAmt, uint256 tokenBAmt);
  event LiquidityRemoved(uint256 lpAmt);
  event ExactTokensForTokensSwapped(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOut,
    uint256 slippage,
    uint256 deadline
  );
  event TokensForExactTokensSwapped(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOut,
    uint256 slippage,
    uint256 deadline
  );

  event EmergencyPaused(
    uint256 repayTokenAAmt,
    uint256 repayTokenBAmt
    );
  event EmergencyResumed();
  event EmergencyResumedCancelled();
  event EmergencyClosed();
  event EmergencyWithdraw(
    address indexed user,
    uint256 sharesAmt,
    address assetA,
    uint256 assetAAmt,
    address assetB,
    uint256 assetBAmt
  );
}

