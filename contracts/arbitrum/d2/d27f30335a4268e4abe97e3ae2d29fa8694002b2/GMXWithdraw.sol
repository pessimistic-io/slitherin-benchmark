// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { ISwap } from "./ISwap.sol";
import { GMXTypes } from "./GMXTypes.sol";
import { GMXReader } from "./GMXReader.sol";
import { GMXChecks } from "./GMXChecks.sol";
import { GMXManager } from "./GMXManager.sol";

/**
  * @title GMXWithdraw
  * @author Steadefi
  * @notice Re-usable library functions for withdraw operations for Steadefi leveraged vaults
*/
library GMXWithdraw {
  using SafeERC20 for IERC20;

  /* ====================== CONSTANTS ======================== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;

  /* ======================== EVENTS ========================= */

  event WithdrawCreated(address indexed user, uint256 shareAmt);
  event WithdrawCompleted(
    address indexed user,
    address token,
    uint256 tokenAmt
  );
  event WithdrawCancelled(address indexed user);
  event WithdrawFailed(bytes reason);

  /* ================== MUTATIVE FUNCTIONS =================== */

  /**
    * @notice @inheritdoc GMXVault
    * @param self GMXTypes.Store
  */
  function withdraw(
    GMXTypes.Store storage self,
    GMXTypes.WithdrawParams memory wp
  ) external {
    self.refundee = payable(msg.sender);

    GMXTypes.HealthParams memory _hp;

    _hp.equityBefore = GMXReader.equityValue(self);
    _hp.lpAmtBefore = GMXReader.lpAmt(self);
    _hp.debtRatioBefore = GMXReader.debtRatio(self);
    _hp.deltaBefore = GMXReader.delta(self);

    GMXTypes.WithdrawCache memory _wc;

    _wc.user = payable(msg.sender);

    _wc.shareRatio = wp.shareAmt
      * SAFE_MULTIPLIER
      / IERC20(address(self.vault)).totalSupply();
    _wc.lpAmt = _wc.shareRatio
      * GMXReader.lpAmt(self)
      / SAFE_MULTIPLIER;
    _wc.withdrawValue = _wc.lpAmt
      * self.gmxOracle.getLpTokenValue(
        address(self.lpToken),
        address(self.tokenA),
        address(self.tokenA),
        address(self.tokenB),
        false,
        false
      )
      / SAFE_MULTIPLIER;

    _wc.withdrawParams = wp;
    _wc.healthParams = _hp;

    (
      uint256 _repayTokenAAmt,
      uint256 _repayTokenBAmt
    ) = GMXManager.calcRepay(self, _wc.shareRatio);

    _wc.repayParams.repayTokenAAmt = _repayTokenAAmt;
    _wc.repayParams.repayTokenBAmt = _repayTokenBAmt;

    self.withdrawCache = _wc;

    GMXChecks.beforeWithdrawChecks(self);

    self.status = GMXTypes.Status.Withdraw;

    self.vault.mintMgmtFee();

    GMXTypes.RemoveLiquidityParams memory _rlp;

    // If user wants to withdraw LP tokens, only remove liquidity of
    // LP tokens that are proportionately borrowed to repay debt
    // If not, we just remove all LP tokens computed in _wc.lpAmt
    if (wp.token == address(self.lpToken)) {
      // LP amount to be removed for leverage debt repayment
      // Multiply LP amt to remove by 2% to account for price differential,
      // fees on LP removal, slippages to ensure payment of debt is covered
      // Excess tokenA/B will be returned to the user regardless
      uint256 _lpAmtToRemove = _wc.lpAmt
        * (self.leverage - SAFE_MULTIPLIER)
        / self.leverage
        * 10200 / 10000;

      _wc.tokensToUser = _wc.lpAmt - _lpAmtToRemove;
      _wc.lpAmt = _lpAmtToRemove;
    }


    // If delta strategy is Long, remove all in tokenB to make it more
    // efficent to repay tokenB debt as Long strategy only borrows tokenB
    if (self.delta == GMXTypes.Delta.Long) {
      address[] memory _tokenASwapPath = new address[](1);
      _tokenASwapPath[0] = address(self.lpToken);
      _rlp.tokenASwapPath = _tokenASwapPath;

      (_rlp.minTokenAAmt, _rlp.minTokenBAmt) = GMXManager.calcMinTokensSlippageAmt(
        self,
        _wc.lpAmt,
        address(self.tokenB),
        address(self.tokenB),
        wp.slippage
      );
    } else {
      (_rlp.minTokenAAmt, _rlp.minTokenBAmt) = GMXManager.calcMinTokensSlippageAmt(
        self,
        _wc.lpAmt,
        address(self.tokenA),
        address(self.tokenB),
        wp.slippage
      );
    }

    _rlp.lpAmt = _wc.lpAmt;
    _rlp.executionFee = wp.executionFee;

    _wc.withdrawKey = GMXManager.removeLiquidity(
      self,
      _rlp
    );

    // Add withdrawKey to store
    self.withdrawCache = _wc;

    emit WithdrawCreated(
      _wc.user,
      _wc.withdrawParams.shareAmt
    );
  }

  /**
    * @notice @inheritdoc GMXVault
    * @param self GMXTypes.Store
  */
  function processWithdraw(
    GMXTypes.Store storage self
  ) external {
    GMXChecks.beforeProcessWithdrawChecks(self);

    GMXTypes.WithdrawCache memory _wc = self.withdrawCache;

    // Check if swap between assets are needed for repayment
    (
      bool _swapNeeded,
      address _tokenFrom,
      address _tokenTo,
      uint256 _tokenToAmt
    ) = GMXManager.calcSwapForRepay(self, _wc.repayParams);

    if (_swapNeeded) {
      ISwap.SwapParams memory _sp;

      _sp.tokenIn = _tokenFrom;
      _sp.tokenOut = _tokenTo;
      _sp.amountIn = IERC20(_tokenFrom).balanceOf(address(this));
      _sp.amountOut = _tokenToAmt;
      _sp.fee = 500;
      _sp.slippage = self.minSlippage;
      _sp.deadline = block.timestamp + 1 minutes;

      GMXManager.swapTokensForExactTokens(self, _sp);
    }

    // Repay debt
    GMXManager.repay(
      self,
      _wc.repayParams.repayTokenAAmt,
      _wc.repayParams.repayTokenBAmt
    );

    // At this point, the LP has been removed for assets for repayment hence
    // equityValue should be less than before. Note that if user wants to withdraw
    // in LP token, the equityValue here should still be less than before as a portion
    // of LP will still have been withdrawn for assets for debt repayment
    _wc.healthParams.equityAfter = GMXReader.equityValue(self);

    self.withdrawCache = _wc;

    // If after withdraw vault checks fail, keeper to call processWithdrawFailure()
    try GMXChecks.afterWithdrawChecks(self) {
      // Swap all tokens for either tokenA/B that user wants
      if (
        _wc.withdrawParams.token == address(self.tokenA) ||
        _wc.withdrawParams.token == address(self.tokenB)
      ) {
        ISwap.SwapParams memory _sp;

        if (_wc.withdrawParams.token == address(self.tokenA)) {
          _sp.tokenIn = address(self.tokenB);
          _sp.tokenOut = address(self.tokenA);
          _sp.amountIn = self.tokenB.balanceOf(address(this));
        }

        if (_wc.withdrawParams.token == address(self.tokenB)) {
          _sp.tokenIn = address(self.tokenA);
          _sp.tokenOut = address(self.tokenB);
          _sp.amountIn = self.tokenA.balanceOf(address(this));
        }

        _sp.fee = 500;
        _sp.slippage = self.minSlippage;
        _sp.deadline = block.timestamp + 1 minutes;

        GMXManager.swapExactTokensForTokens(self, _sp);

        _wc.tokensToUser = IERC20(_wc.withdrawParams.token).balanceOf(address(this));
      }

      // If native token is being withdrawn, we convert wrapped to native
      if (_wc.withdrawParams.token == address(self.WNT)) {
        self.WNT.withdraw(self.WNT.balanceOf(address(this)));
        (bool success, ) = _wc.user.call{value: address(this).balance}("");
        require(success, "Transfer failed.");
      } else {
        // Transfer requested withdraw asset to user
        IERC20(_wc.withdrawParams.token).safeTransfer(
          _wc.user,
          _wc.tokensToUser
        );
      }

      // Transfer any remaining tokenA/B that was unused (due to slippage) to user as well
      self.tokenA.safeTransfer(_wc.user, self.tokenA.balanceOf(address(this)));
      self.tokenB.safeTransfer(_wc.user, self.tokenB.balanceOf(address(this)));

      // Burn user shares
      self.vault.burn(_wc.user, _wc.withdrawParams.shareAmt);

      emit WithdrawCompleted(
        _wc.user,
        _wc.withdrawParams.token,
        _wc.tokensToUser
      );

      self.status = GMXTypes.Status.Open;
    } catch (bytes memory reason) {
      self.status = GMXTypes.Status.Withdraw_Failed;

      emit WithdrawFailed(reason);
    }
  }

  /**
    * @notice @inheritdoc GMXVault
    * @param self GMXTypes.Store
  */
  function processWithdrawCancellation(
    GMXTypes.Store storage self
  ) external {
    GMXChecks.beforeProcessWithdrawCancellationChecks(self);

    emit WithdrawCancelled(self.withdrawCache.user);

    self.status = GMXTypes.Status.Open;
  }

  /**
    * @notice @inheritdoc GMXVault
    * @param self GMXTypes.Store
  */
  function processWithdrawFailure(
    GMXTypes.Store storage self,
    uint256 slippage,
    uint256 executionFee
  ) external {
    GMXChecks.beforeProcessAfterWithdrawFailureChecks(self);

    // Re-borrow assets based on the repaid amount
    GMXManager.borrow(
      self,
      self.withdrawCache.repayParams.repayTokenAAmt,
      self.withdrawCache.repayParams.repayTokenBAmt
    );

    // Re-add liquidity using all available tokenA/B in vault
    GMXTypes.AddLiquidityParams memory _alp;

    _alp.tokenAAmt = self.tokenA.balanceOf(address(this));
    _alp.tokenBAmt = self.tokenB.balanceOf(address(this));

    // Calculate slippage
    uint256 _depositValue = GMXReader.convertToUsdValue(
      self,
      address(self.tokenA),
      self.tokenA.balanceOf(address(this))
    )
    + GMXReader.convertToUsdValue(
      self,
      address(self.tokenB),
      self.tokenB.balanceOf(address(this))
    );

    _alp.minMarketTokenAmt = GMXManager.calcMinMarketSlippageAmt(
      self,
      _depositValue,
      slippage
    );
    _alp.executionFee = executionFee;

    // Re-add liquidity with all tokenA/tokenB in vault
    self.withdrawCache.depositKey = GMXManager.addLiquidity(
      self,
      _alp
    );
  }

  /**
    * @notice @inheritdoc GMXVault
    * @param self GMXTypes.Store
  */
  function processWithdrawFailureLiquidityAdded(
    GMXTypes.Store storage self
  ) external {
    GMXChecks.beforeProcessAfterWithdrawFailureLiquidityAdded(self);

    self.status = GMXTypes.Status.Open;
  }
}

