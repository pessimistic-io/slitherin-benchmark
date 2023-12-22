// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { GMXTypes } from "./GMXTypes.sol";
import { GMXReader } from "./GMXReader.sol";
import { GMXChecks } from "./GMXChecks.sol";
import { GMXManager } from "./GMXManager.sol";
import { GMXEmergency } from "./GMXEmergency.sol";

/**
  * @title GMXRebalance
  * @author Steadefi
  * @notice Re-usable library functions for rebalancing operations for Steadefi leveraged vaults
*/
library GMXRebalance {

  /* ======================== EVENTS ========================= */

  event RebalanceAdded(
    uint rebalanceType,
    uint256 borrowTokenAAmt,
    uint256 borrowTokenBAmt
  );
  event RebalanceAddProcessed();
  event RebalanceRemoved(
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

  /* ================== MUTATIVE FUNCTIONS =================== */

  /**
    * @notice @inheritdoc GMXVault
    * @param self GMXTypes.Store
  */
  function rebalanceAdd(
    GMXTypes.Store storage self,
    GMXTypes.RebalanceAddParams memory rap
  ) external {
    self.refundee = payable(msg.sender);

    GMXTypes.HealthParams memory _hp;

    _hp.lpAmtBefore = GMXReader.lpAmt(self);
    _hp.debtRatioBefore = GMXReader.debtRatio(self);
    _hp.deltaBefore = GMXReader.delta(self);
    _hp.svTokenValueBefore = GMXReader.svTokenValue(self);

    GMXTypes.RebalanceCache memory _rc;

    _rc.rebalanceType = rap.rebalanceType;
    _rc.borrowParams = rap.borrowParams;
    _rc.healthParams = _hp;

    self.rebalanceCache = _rc;

    GMXChecks.beforeRebalanceChecks(self, rap.rebalanceType);

    self.status = GMXTypes.Status.Rebalance_Add;

    GMXManager.borrow(
      self,
      rap.borrowParams.borrowTokenAAmt,
      rap.borrowParams.borrowTokenBAmt
    );

    GMXTypes.AddLiquidityParams memory _alp;

    _alp.tokenAAmt = rap.borrowParams.borrowTokenAAmt;
    _alp.tokenBAmt = rap.borrowParams.borrowTokenBAmt;

    // Calculate deposit value after borrows and repays
    // Rebalance will only deal with tokenA and tokenB and not LP tokens
    uint256 _depositValue = GMXReader.convertToUsdValue(
      self,
      address(self.tokenA),
      _alp.tokenAAmt
    )
    + GMXReader.convertToUsdValue(
      self,
      address(self.tokenB),
      _alp.tokenBAmt
    );

    _alp.minMarketTokenAmt = GMXManager.calcMinMarketSlippageAmt(
      self,
      _depositValue,
      self.liquiditySlippage
    );

    _alp.executionFee = rap.executionFee;

    self.rebalanceCache.depositKey = GMXManager.addLiquidity(
      self,
      _alp
    );

    emit RebalanceAdded(
      uint(rap.rebalanceType),
      rap.borrowParams.borrowTokenAAmt,
      rap.borrowParams.borrowTokenBAmt
    );
  }

  /**
    * @notice @inheritdoc GMXVault
    * @param self GMXTypes.Store
  */
  function processRebalanceAdd(
    GMXTypes.Store storage self,
    uint256 lpAmtReceived
  ) external {
    GMXChecks.beforeProcessRebalanceChecks(self);

    self.lpAmt += lpAmtReceived;

    try GMXChecks.afterRebalanceChecks(self) {
      self.status = GMXTypes.Status.Open;

      emit RebalanceSuccess(
        self.rebalanceCache.healthParams.svTokenValueBefore,
        GMXReader.svTokenValue(self)
      );
    } catch (bytes memory reason) {
      self.status = GMXTypes.Status.Rebalance_Open;

      emit RebalanceOpen(
        reason,
        self.rebalanceCache.healthParams.svTokenValueBefore,
        GMXReader.svTokenValue(self)
      );
    }

    // Check if there is an emergency pause queued
    if (self.shouldEmergencyPause) GMXEmergency.emergencyPause(self);

    emit RebalanceAddProcessed();
  }

  /**
    * @notice @inheritdoc GMXVault
    * @param self GMXTypes.Store
  */
  function processRebalanceAddCancellation(
    GMXTypes.Store storage self
  ) external {
    GMXChecks.beforeProcessRebalanceChecks(self);

    GMXManager.repay(
      self,
      self.rebalanceCache.borrowParams.borrowTokenAAmt,
      self.rebalanceCache.borrowParams.borrowTokenBAmt
    );

    self.status = GMXTypes.Status.Open;

    // Check if there is an emergency pause queued
    if (self.shouldEmergencyPause) GMXEmergency.emergencyPause(self);

    emit RebalanceCancelled();
  }

  /**
    * @notice @inheritdoc GMXVault
    * @param self GMXTypes.Store
  */
  function rebalanceRemove(
    GMXTypes.Store storage self,
    GMXTypes.RebalanceRemoveParams memory rrp
  ) external {
    self.refundee = payable(msg.sender);

    GMXTypes.HealthParams memory _hp;

    _hp.lpAmtBefore = GMXReader.lpAmt(self);
    _hp.debtRatioBefore = GMXReader.debtRatio(self);
    _hp.deltaBefore = GMXReader.delta(self);
    _hp.svTokenValueBefore = GMXReader.svTokenValue(self);

    GMXTypes.RebalanceCache memory _rc;

    _rc.rebalanceType = rrp.rebalanceType;
    _rc.lpAmtToRemove = rrp.lpAmtToRemove;
    _rc.healthParams = _hp;

    self.rebalanceCache = _rc;

    GMXChecks.beforeRebalanceChecks(self, rrp.rebalanceType);

    self.status = GMXTypes.Status.Rebalance_Remove;

    self.lpAmt -= rrp.lpAmtToRemove;

    GMXTypes.RemoveLiquidityParams memory _rlp;

    if (rrp.rebalanceType == GMXTypes.RebalanceType.Delta) {
      // When rebalancing delta, repay only tokenA so withdraw liquidity only in tokenA
      address[] memory _tokenBSwapPath = new address[](1);
      _tokenBSwapPath[0] = address(self.lpToken);
      _rlp.tokenBSwapPath = _tokenBSwapPath;

      (_rlp.minTokenAAmt, _rlp.minTokenBAmt) = GMXManager.calcMinTokensSlippageAmt(
        self,
        rrp.lpAmtToRemove,
        address(self.tokenA),
        address(self.tokenA),
        self.liquiditySlippage
      );
    } else if (rrp.rebalanceType == GMXTypes.RebalanceType.Debt) {
      // When rebalancing debt, repay only tokenB so withdraw liquidity only in tokenB
      address[] memory _tokenASwapPath = new address[](1);
      _tokenASwapPath[0] = address(self.lpToken);
      _rlp.tokenASwapPath = _tokenASwapPath;

      (_rlp.minTokenAAmt, _rlp.minTokenBAmt) = GMXManager.calcMinTokensSlippageAmt(
        self,
        rrp.lpAmtToRemove,
        address(self.tokenB),
        address(self.tokenB),
        self.liquiditySlippage
      );
    }

    _rlp.lpAmt = rrp.lpAmtToRemove;
    _rlp.executionFee = rrp.executionFee;

    self.rebalanceCache.withdrawKey = GMXManager.removeLiquidity(
      self,
      _rlp
    );

    emit RebalanceRemoved(
      uint(rrp.rebalanceType),
      rrp.lpAmtToRemove
    );
  }

  /**
    * @notice @inheritdoc GMXVault
    * @param self GMXTypes.Store
  */
  function processRebalanceRemove(
    GMXTypes.Store storage self,
    uint256 tokenAReceived,
    uint256 tokenBReceived
  ) external {
    GMXChecks.beforeProcessRebalanceChecks(self);

    // As we convert LP tokens in rebalanceRemove() to receive assets in as:
    // Delta: 100% tokenA
    // Debt: 100% tokenB
    // The tokenAReceived/tokenBReceived values could both be amounts of the same token.
    // As such we look to "sanitise" the data here such that for e.g., if we had wanted only
    // tokenA from withdrawal of the LP tokens, we will add tokenBReceived to tokenAReceived and
    // clear out tokenBReceived to 0.
    if (self.rebalanceCache.rebalanceType == GMXTypes.RebalanceType.Delta) {
      // We withdraw assets all in tokenA
      self.withdrawCache.tokenAReceived = tokenAReceived + tokenBReceived;
      self.withdrawCache.tokenBReceived = 0;
    } else if (self.rebalanceCache.rebalanceType == GMXTypes.RebalanceType.Debt) {
      // We withdraw assets all in tokenB
      self.withdrawCache.tokenAReceived = 0;
      self.withdrawCache.tokenBReceived = tokenAReceived + tokenBReceived;
    }

    GMXManager.repay(
      self,
      tokenAReceived,
      tokenBReceived
    );

    try GMXChecks.afterRebalanceChecks(self) {
      self.status = GMXTypes.Status.Open;

      emit RebalanceSuccess(
        self.rebalanceCache.healthParams.svTokenValueBefore,
        GMXReader.svTokenValue(self)
      );
    } catch (bytes memory reason) {
      self.status = GMXTypes.Status.Rebalance_Open;

      emit RebalanceOpen(
        reason,
        self.rebalanceCache.healthParams.svTokenValueBefore,
        GMXReader.svTokenValue(self)
      );
    }

    // Check if there is an emergency pause queued
    if (self.shouldEmergencyPause) GMXEmergency.emergencyPause(self);

    emit RebalanceRemoveProcessed();
  }

  /**
    * @dev Process cancellation after processRebalanceRemoveCancellation()
    * @param self Vault store data
  **/
  function processRebalanceRemoveCancellation(
    GMXTypes.Store storage self
  ) external {
    GMXChecks.beforeProcessRebalanceChecks(self);

    self.lpAmt += self.rebalanceCache.lpAmtToRemove;

    self.status = GMXTypes.Status.Open;

    // Check if there is an emergency pause queued
    if (self.shouldEmergencyPause) GMXEmergency.emergencyPause(self);

    emit RebalanceCancelled();
  }
}

