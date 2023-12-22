// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { ISwap } from "./ISwap.sol";
import { GMXTypes } from "./GMXTypes.sol";
import { GMXChecks } from "./GMXChecks.sol";
import { GMXManager } from "./GMXManager.sol";
import { GMXReader } from "./GMXReader.sol";
import { GMXEmergency } from "./GMXEmergency.sol";

/**
  * @title GMXCompound
  * @author Steadefi
  * @notice Re-usable library functions for compound operations for Steadefi leveraged vaults
*/
library GMXCompound {
  using SafeERC20 for IERC20;

  /* ====================== CONSTANTS ======================== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;

  /* ======================== EVENTS ========================= */

  event CompoundCompleted();
  event CompoundCancelled();

  /* ================== MUTATIVE FUNCTIONS =================== */

  /**
    * @notice @inheritdoc GMXVault
    * @param self GMXTypes.Store
  */
  function compound(
    GMXTypes.Store storage self,
    GMXTypes.CompoundParams memory cp
  ) external {
    self.refundee = payable(msg.sender);

    self.compoundCache.compoundParams = cp;

    ISwap.SwapParams memory _sp;

    _sp.tokenIn = cp.tokenIn;
    _sp.tokenOut = cp.tokenOut;
    _sp.amountIn = cp.amtIn;
    _sp.amountOut = 0; // amount out minimum calculated in Swap
    _sp.slippage = self.swapSlippage;
    _sp.deadline = cp.deadline;

    uint256 _amountOut = GMXManager.swapExactTokensForTokens(self, _sp);

    GMXTypes.AddLiquidityParams memory _alp;

    if (cp.tokenOut == address(self.tokenA)) {
      _alp.tokenAAmt = _amountOut;
    } else if (cp.tokenOut == address(self.tokenB)) {
      _alp.tokenBAmt = _amountOut;
    }

    // Only add liquidity if tokenA/B is more than 0
    if (_alp.tokenAAmt > 0 || _alp.tokenBAmt > 0) {
      if (_alp.tokenAAmt > 0) {
        self.compoundCache.depositValue = GMXReader.convertToUsdValue(
          self,
          address(self.tokenA),
          _alp.tokenAAmt
        );
      } else if (_alp.tokenBAmt > 0) {
        self.compoundCache.depositValue = GMXReader.convertToUsdValue(
          self,
          address(self.tokenB),
          _alp.tokenBAmt
        );
      }

      GMXChecks.beforeCompoundChecks(self);

      self.status = GMXTypes.Status.Compound;

      _alp.minMarketTokenAmt = GMXManager.calcMinMarketSlippageAmt(
        self,
        self.compoundCache.depositValue,
        self.liquiditySlippage
      );

      _alp.executionFee = cp.executionFee;

      self.compoundCache.depositKey = GMXManager.addLiquidity(
        self,
        _alp
      );
    }
  }

  /**
    * @notice @inheritdoc GMXVault
    * @param self GMXTypes.Store
  */
  function processCompound(
    GMXTypes.Store storage self,
    uint256 lpAmtReceived
  ) external {
    GMXChecks.beforeProcessCompoundChecks(self);

    self.lpAmt += lpAmtReceived;

    self.status = GMXTypes.Status.Open;

    // Check if there is an emergency pause queued
    if (self.shouldEmergencyPause) GMXEmergency.emergencyPause(self);

    emit CompoundCompleted();
  }

  /**
    * @notice @inheritdoc GMXVault
    * @param self GMXTypes.Store
  */
  function processCompoundCancellation(
    GMXTypes.Store storage self
  ) external {
    GMXChecks.beforeProcessCompoundCancellationChecks(self);

    self.status = GMXTypes.Status.Open;

    emit CompoundCancelled();
  }
}

