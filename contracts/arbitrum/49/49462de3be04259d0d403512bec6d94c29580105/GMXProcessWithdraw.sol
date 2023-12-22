// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { ISwap } from "./ISwap.sol";
import { GMXTypes } from "./GMXTypes.sol";
import { GMXReader } from "./GMXReader.sol";
import { GMXChecks } from "./GMXChecks.sol";
import { GMXManager } from "./GMXManager.sol";

/**
  * @title GMXProcessWithdraw
  * @author Steadefi
  * @notice Re-usable library functions for process withdraw operations for Steadefi leveraged vaults
*/
library GMXProcessWithdraw {

  /* ================== MUTATIVE FUNCTIONS =================== */

  /**
    * @notice @inheritdoc GMXVault
    * @param self GMXTypes.Store
  */
  function processWithdraw(
    GMXTypes.Store storage self
  ) external {
    // Check if swap between assets are needed for repayment
    (
      bool _swapNeeded,
      address _tokenFrom,
      address _tokenTo,
      uint256 _tokenToAmt
    ) = GMXManager.calcSwapForRepay(
      self,
      self.withdrawCache.repayParams,
      self.withdrawCache.tokenAReceived,
      self.withdrawCache.tokenBReceived
    );

    // Swap likely only needed if vault strategy is Neutral as we borrow both tokenA and tokenB
    if (_swapNeeded) {
      ISwap.SwapParams memory _sp;

      _sp.tokenIn = _tokenFrom;
      _sp.tokenOut = _tokenTo;
      _sp.amountIn = GMXManager.calcAmountInMaximum(
        self,
        _tokenFrom,
        _tokenTo,
        _tokenToAmt
      );
      _sp.amountOut = _tokenToAmt;
      _sp.slippage = self.swapSlippage;
      _sp.deadline = block.timestamp;
      // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
      // We allow deadline to be set as the current block timestamp whenever this function
      // is called because this function is triggered as a follow up function (by a callback/keeper)
      // and not directly by a user/keeper. If this follow on function flow reverts due to this tx
      // being processed after a set deadline, this will cause the vault to be in a "stuck" state.
      // To resolve this, this function will have to be called again with an updated deadline until it
      // succeeds/a miner processes the tx.

      uint256 _amountIn = GMXManager.swapTokensForExactTokens(self, _sp);

      if (_tokenFrom == address(self.tokenA)) {
        self.withdrawCache.tokenAReceived -= _amountIn;
        self.withdrawCache.tokenBReceived += _tokenToAmt;
      } else if (_tokenFrom == address(self.tokenB)) {
        self.withdrawCache.tokenBReceived -= _amountIn;
        self.withdrawCache.tokenAReceived += _tokenToAmt;
      }
    }

    // Repay debt
    GMXManager.repay(
      self,
      self.withdrawCache.repayParams.repayTokenAAmt,
      self.withdrawCache.repayParams.repayTokenBAmt
    );

    self.withdrawCache.tokenAReceived -= self.withdrawCache.repayParams.repayTokenAAmt;
    self.withdrawCache.tokenBReceived -= self.withdrawCache.repayParams.repayTokenBAmt;

    // At this point, the LP has been accounted to be removed for withdrawal so
    // equityValue should be less than before
    self.withdrawCache.healthParams.equityAfter = GMXReader.equityValue(self);

    if (
      self.withdrawCache.withdrawParams.token == address(self.tokenA) &&
      self.withdrawCache.tokenBReceived > 0
    ) {
      ISwap.SwapParams memory _sp;

      _sp.tokenIn = address(self.tokenB);
      _sp.tokenOut = address(self.tokenA);
      _sp.amountIn = self.withdrawCache.tokenBReceived;
      _sp.slippage = self.swapSlippage;
      _sp.deadline = block.timestamp;
      // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
      // We allow deadline to be set as the current block timestamp whenever this function
      // is called because this function is triggered as a follow up function (by a callback/keeper)
      // and not directly by a user/keeper. If this follow on function flow reverts due to this tx
      // being processed after a set deadline, this will cause the vault to be in a "stuck" state.
      // To resolve this, this function will have to be called again with an updated deadline until it
      // succeeds/a miner processes the tx.

      uint256 _amountOut = GMXManager.swapExactTokensForTokens(self, _sp);

      self.withdrawCache.tokenAReceived += _amountOut;
      self.withdrawCache.assetsToUser = self.withdrawCache.tokenAReceived;
    }

    if (
      self.withdrawCache.withdrawParams.token == address(self.tokenB) &&
      self.withdrawCache.tokenAReceived > 0
    ) {
      ISwap.SwapParams memory _sp;

      _sp.tokenIn = address(self.tokenA);
      _sp.tokenOut = address(self.tokenB);
      _sp.amountIn = self.withdrawCache.tokenAReceived;
      _sp.slippage = self.swapSlippage;
      _sp.deadline = block.timestamp;
      // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
      // We allow deadline to be set as the current block timestamp whenever this function
      // is called because this function is triggered as a follow up function (by a callback/keeper)
      // and not directly by a user/keeper. If this follow on function flow reverts due to this tx
      // being processed after a set deadline, this will cause the vault to be in a "stuck" state.
      // To resolve this, this function will have to be called again with an updated deadline until it
      // succeeds/a miner processes the tx.

      uint256 _amountOut = GMXManager.swapExactTokensForTokens(self, _sp);

      self.withdrawCache.tokenBReceived += _amountOut;
      self.withdrawCache.assetsToUser = self.withdrawCache.tokenBReceived;
    }

    // After withdraws checks to be done outside of if block to also cover for LP withdrawal flow
    GMXChecks.afterWithdrawChecks(self);
  }
}

