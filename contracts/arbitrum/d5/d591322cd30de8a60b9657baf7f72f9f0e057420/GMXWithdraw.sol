// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { GMXTypes } from "./GMXTypes.sol";
import { GMXReader } from "./GMXReader.sol";
import { GMXChecks } from "./GMXChecks.sol";
import { GMXManager } from "./GMXManager.sol";

library GMXWithdraw {
  using SafeERC20 for IERC20;

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;

  /* ========== EVENTS ========== */

  event WithdrawCreated(address indexed user, uint256 shareAmt);
  event WithdrawCompleted(
    address indexed user,
    address token,
    uint256 tokenAmt
  );

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
    * @dev Withdraws asset from vault, burns svToken from user
    * @param self Vault store data
    * @param wp WithdrawParams struct of withdraw parameters
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

    _wc.shareRatio = wp.shareAmt
      * SAFE_MULTIPLIER
      / IERC20(address(self.vault)).totalSupply();
    _wc.lpAmt = _wc.shareRatio
      * GMXReader.lpAmt(self)
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

    self.status = GMXTypes.Status.Remove_Liquidity;

    GMXTypes.RemoveLiquidityParams memory _rlp;

    // If user wants to withdraw LP tokens, we should only remove liquidity of the LP tokens that are proportionately borrowed to repay debt
    // If not, we just remove all LP tokens
    if (wp.token == address(self.lpToken)) {
      uint256 _repayValue = GMXReader.convertToUsdValue(
        self,
        address(self.tokenA),
        _wc.repayParams.repayTokenAAmt
      )
      + GMXReader.convertToUsdValue(
        self,
        address(self.tokenB),
        _wc.repayParams.repayTokenBAmt
      );

      // Adjust LP amount to remove only for repaying debt
      uint256 _lpAmtToRemove = _repayValue
        * SAFE_MULTIPLIER
        / self.gmxOracle.getLpTokenValue(
          address(self.lpToken),
          address(self.tokenA),
          address(self.tokenA),
          address(self.tokenB),
          false,
          false
        );

      _wc.tokensToUser = _wc.lpAmt - _lpAmtToRemove;
      _wc.lpAmt = _lpAmtToRemove;
    }

    // Delta long strategy to withdraw in all tokenB
    // as debt will all be in tokenB first
    if (self.delta == GMXTypes.Delta.Long) {
      _rlp.tokenASwapPath[0] = address(self.lpToken);
    }

    _rlp.lpAmt = _wc.lpAmt;

    (
      _rlp.minTokenAAmt,
      _rlp.minTokenBAmt
    ) = GMXManager.calcMinTokensSlippageAmt(
      self,
      _rlp.lpAmt,
      wp.slippage
    );

    _rlp.executionFee = wp.executionFee;

    _wc.withdrawKey = GMXManager.removeLiquidity(
      self,
      _rlp
    );

    // Add withdrawKey to store
    self.withdrawCache = _wc;

    self.status = GMXTypes.Status.Swap_For_Repay;

    emit WithdrawCreated(
      self.refundee,
      _wc.withdrawParams.shareAmt
    );
  }

  /**
    * @dev Determine if swap is required for repayment after withdrawal of LP
    * @notice Called by keeper via Event Emitted from GMX
    * @param self Vault store data
  */
  function processSwapForRepay(
    GMXTypes.Store storage self
  ) external {
    GMXChecks.processSwapForRepayChecks(self);

    GMXTypes.WithdrawCache memory _wc = self.withdrawCache;

    // Check if swap between assets are needed for repayment
    (
      bool _swapNeeded,
      address _tokenFrom,
      address _tokenTo,
      uint256 _tokenFromAmt
    ) = GMXManager.calcSwapForRepay(self, _wc.repayParams);

    if (_swapNeeded) {
      GMXTypes.SwapParams memory _sp;
      _sp.tokenIn = _tokenFrom;
      _sp.tokenOut = _tokenTo;
      _sp.amountIn = _tokenFromAmt;
      _sp.slippage = _wc.withdrawParams.swapSlippage;
      _sp.deadline = _wc.withdrawParams.swapDeadline;

      GMXManager.swap(self, _sp);
    }

    self.withdrawCache = _wc;

    self.status = GMXTypes.Status.Repay;

    processRepay(self);
  }

  /**
    * @dev Repay debt and check if swap for withdrawal is needed
    * @notice Called by keeper via Event Emitted from GMX
    * @notice orderKey can be bytes32(0) if there is no swap needed for repay
    * @param self Vault store data
  */
  function processRepay(
    GMXTypes.Store storage self
  ) public {
    GMXChecks.processRepayChecks(self);

    GMXTypes.WithdrawCache memory _wc = self.withdrawCache;

    // Repay debt
    GMXManager.repay(
      self,
      _wc.repayParams.repayTokenAAmt,
      _wc.repayParams.repayTokenBAmt
    );

    self.status = GMXTypes.Status.Swap_For_Withdraw;

    self.status = GMXTypes.Status.Burn;

    processBurn(self);
  }

  /**
    * @dev Process burning of shares and sending of assets to user after swap for withdraw
    * @notice Called by keeper via Event Emitted from GMX
    * @notice orderKey can be bytes32(0) if there is no swap needed for repay
    * @param self Vault store data
  */
  function processBurn(
    GMXTypes.Store storage self
  ) public {
    GMXChecks.processBurnChecks(self);

    GMXTypes.WithdrawCache memory _wc = self.withdrawCache;

    // If user withdraw token is tokenA or tokenB, we get how many tokenA/block is currently in vault after repayment
    // Else the amount of LP token is already calculated beforehand
    if (
      _wc.withdrawParams.token == address(self.tokenA) ||
      _wc.withdrawParams.token == address(self.tokenB)
    ) {
      _wc.tokensToUser = IERC20(_wc.withdrawParams.token).balanceOf(address(this));
    }

    // Transfer requested withdraw asset to user
    IERC20(_wc.withdrawParams.token).safeTransfer(
      self.refundee,
      _wc.tokensToUser
    );

    // Burn user shares
    self.vault.burn(self.refundee, _wc.withdrawParams.shareAmt);

    // Get state of vault after
    _wc.healthParams.equityAfter = GMXReader.equityValue(self);

    self.withdrawCache = _wc;

    GMXChecks.afterWithdrawChecks(self);

    emit WithdrawCompleted(
      self.refundee,
      _wc.withdrawParams.token,
      _wc.tokensToUser
    );

    self.refundee = payable(address(0));
    delete self.withdrawCache;

    self.status = GMXTypes.Status.Open;
  }
}

