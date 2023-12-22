// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { IERC20Metadata } from "./IERC20Metadata.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { GMXTypes } from "./GMXTypes.sol";
import { GMXReader } from "./GMXReader.sol";
import { GMXChecks } from "./GMXChecks.sol";
import { GMXManager } from "./GMXManager.sol";
import { GMXProcessWithdraw } from "./GMXProcessWithdraw.sol";
import { GMXEmergency } from "./GMXEmergency.sol";

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
  event WithdrawFailureProcessed();
  event WithdrawFailureLiquidityAddedProcessed();

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

    // Mint fee before calculating shareRatio for correct totalSupply
    self.vault.mintFee();

    // Calculate user share ratio
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
        true,
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

    // Calculate minimum amount of assets expected based on shares to burn
    // and vault slippage value passed in. We calculate this after `beforeWithdrawChecks()`
    // to ensure the vault slippage passed in meets the `minVaultSlippage`.
    // minAssetsAmt = userVaultSharesAmt * vaultSvTokenValue / assetToReceiveValue x slippage
    _wc.minAssetsAmt = wp.shareAmt
      * GMXReader.svTokenValue(self)
      / self.chainlinkOracle.consultIn18Decimals(address(wp.token))
      * (10000 - wp.slippage) / 10000;

    // minAssetsAmt is in 1e18. If asset decimals is less than 18, e.g. USDC,
    // we need to normalize the decimals of minAssetsAmt
    if (IERC20Metadata(wp.token).decimals() < 18)
      _wc.minAssetsAmt /= 10 ** (18 - IERC20Metadata(wp.token).decimals());

    // Burn user shares
    self.vault.burn(self.withdrawCache.user, self.withdrawCache.withdrawParams.shareAmt);

    self.status = GMXTypes.Status.Withdraw;

    // Account LP tokens removed from vault
    self.lpAmt -= _wc.lpAmt;

    GMXTypes.RemoveLiquidityParams memory _rlp;

    if (self.delta == GMXTypes.Delta.Long) {
      // If delta strategy is Long, remove all in tokenB to make it more
      // efficent to repay tokenB debt as Long strategy only borrows tokenB
      address[] memory _tokenASwapPath = new address[](1);
      _tokenASwapPath[0] = address(self.lpToken);
      _rlp.tokenASwapPath = _tokenASwapPath;

      (_rlp.minTokenAAmt, _rlp.minTokenBAmt) = GMXManager.calcMinTokensSlippageAmt(
        self,
        _wc.lpAmt,
        address(self.tokenB),
        address(self.tokenB),
        self.liquiditySlippage
      );
    } else if (self.delta == GMXTypes.Delta.Short) {
      // If delta strategy is Short, remove all in tokenA to make it more
      // efficent to repay tokenA debt as Short strategy only borrows tokenA
      address[] memory _tokenBSwapPath = new address[](1);
      _tokenBSwapPath[0] = address(self.lpToken);
      _rlp.tokenBSwapPath = _tokenBSwapPath;

      (_rlp.minTokenAAmt, _rlp.minTokenBAmt) = GMXManager.calcMinTokensSlippageAmt(
        self,
        _rlp.lpAmt,
        address(self.tokenA),
        address(self.tokenA),
        self.liquiditySlippage
      );
    } else {
      // If delta strategy is Neutral, withdraw in both tokenA/B
      (_rlp.minTokenAAmt, _rlp.minTokenBAmt) = GMXManager.calcMinTokensSlippageAmt(
        self,
        _wc.lpAmt,
        address(self.tokenA),
        address(self.tokenB),
        self.liquiditySlippage
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
    GMXTypes.Store storage self,
    uint256 tokenAReceived,
    uint256 tokenBReceived
  ) external {
    GMXChecks.beforeProcessWithdrawChecks(self);

    // As we convert LP tokens in withdraw() to receive assets in as:
    // Delta Short: 100% tokenA
    // Delta Long: 100% tokenB
    // Delta Neutral: tokenA/B in tokenWeights in GM pool
    // The tokenAReceived/tokenBReceived values could both be amounts of the same token.
    // As such we look to "sanitise" the data here such that for e.g., if we had wanted only
    // tokenA from withdrawal of the LP tokens, we will add tokenBReceived to tokenAReceived and
    // clear out tokenBReceived to 0.
    if (self.delta == GMXTypes.Delta.Long) {
      // We withdraw assets all in tokenB
      self.withdrawCache.tokenAReceived = 0;
      self.withdrawCache.tokenBReceived = tokenAReceived + tokenBReceived;
    } else if (self.delta == GMXTypes.Delta.Long) {
      // We withdraw assets all in tokenA
      self.withdrawCache.tokenAReceived = tokenAReceived + tokenBReceived;
      self.withdrawCache.tokenBReceived = 0;
    } else {
      // Both tokenA/B amount received are "correct" for their respective tokens
      self.withdrawCache.tokenAReceived = tokenAReceived;
      self.withdrawCache.tokenBReceived = tokenBReceived;
    }

    // We transfer the core logic of this function to GMXProcessWithdraw.processWithdraw()
    // to allow try/catch here to catch for any issues such as any token swaps failing or
    // debt repayment failing, or any checks in afterWithdrawChecks() failing.
    // If there are any issues, a WithdrawFailed event will be emitted and processWithdrawFailure()
    // should be triggered to refund assets accordingly and reset the vault status to Open again.
    try GMXProcessWithdraw.processWithdraw(self) {
      // If native token is being withdrawn, we convert wrapped to native
      if (self.withdrawCache.withdrawParams.token == address(self.WNT)) {
        self.WNT.withdraw(self.withdrawCache.assetsToUser);
        (bool success, ) = self.withdrawCache.user.call{
          value: self.withdrawCache.assetsToUser
        }("");
        // if native transfer unsuccessful, send WNT back to user
        if (!success) {
          self.WNT.deposit{value: self.withdrawCache.assetsToUser}();
          IERC20(address(self.WNT)).safeTransfer(
            self.withdrawCache.user,
            self.withdrawCache.assetsToUser
          );
        }
      } else {
        // Transfer requested withdraw asset to user
        IERC20(self.withdrawCache.withdrawParams.token).safeTransfer(
          self.withdrawCache.user,
          self.withdrawCache.assetsToUser
        );
      }

      self.status = GMXTypes.Status.Open;

      // Check if there is an emergency pause queued
      if (self.shouldEmergencyPause) GMXEmergency.emergencyPause(self);

      emit WithdrawCompleted(
        self.withdrawCache.user,
        self.withdrawCache.withdrawParams.token,
        self.withdrawCache.assetsToUser
      );
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

    self.status = GMXTypes.Status.Open;

    // Check if there is an emergency pause queued
    if (self.shouldEmergencyPause) GMXEmergency.emergencyPause(self);

    emit WithdrawCancelled(self.withdrawCache.user);
  }

  /**
    * @notice @inheritdoc GMXVault
    * @param self GMXTypes.Store
  */
  function processWithdrawFailure(
    GMXTypes.Store storage self,
    uint256 executionFee
  ) external {
    GMXChecks.beforeProcessWithdrawFailureChecks(self);

    self.refundee = payable(msg.sender);

    // Refund users their burnt shares
    self.vault.mint(self.withdrawCache.user, self.withdrawCache.withdrawParams.shareAmt);

    // Re-add liquidity using all available tokenA/B in vault
    GMXTypes.AddLiquidityParams memory _alp;

    _alp.tokenAAmt = self.withdrawCache.tokenAReceived;
    _alp.tokenBAmt = self.withdrawCache.tokenBReceived;

    // Calculate slippage
    uint256 _depositValue = GMXReader.convertToUsdValue(
      self,
      address(self.tokenA),
      self.withdrawCache.tokenAReceived
    )
    + GMXReader.convertToUsdValue(
      self,
      address(self.tokenB),
      self.withdrawCache.tokenBReceived
    );

    _alp.minMarketTokenAmt = GMXManager.calcMinMarketSlippageAmt(
      self,
      _depositValue,
      self.liquiditySlippage
    );
    _alp.executionFee = executionFee;

    // Re-add liquidity with all tokenA/tokenB in vault
    self.withdrawCache.depositKey = GMXManager.addLiquidity(
      self,
      _alp
    );

    emit WithdrawFailureProcessed();
  }

  /**
    * @notice @inheritdoc GMXVault
    * @param self GMXTypes.Store
  */
  function processWithdrawFailureLiquidityAdded(
    GMXTypes.Store storage self,
    uint256 lpAmtReceived
  ) external {
    GMXChecks.beforeProcessWithdrawFailureLiquidityAdded(self);

    self.lpAmt += lpAmtReceived;

    self.status = GMXTypes.Status.Open;

    // Check if there is an emergency pause queued
    if (self.shouldEmergencyPause) GMXEmergency.emergencyPause(self);

    emit WithdrawFailureLiquidityAddedProcessed();
  }
}

