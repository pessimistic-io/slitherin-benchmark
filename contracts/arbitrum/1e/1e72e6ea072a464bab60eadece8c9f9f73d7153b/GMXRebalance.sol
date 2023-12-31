// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { GMXTypes } from "./GMXTypes.sol";
import { GMXReader } from "./GMXReader.sol";
import { GMXChecks } from "./GMXChecks.sol";
import { GMXManager } from "./GMXManager.sol";

library GMXRebalance {

  /* ========== EVENTS ========== */

  event RebalanceSuccess(uint256 svTokenValueBefore, uint256 svTokenValueAfter);
  event RebalanceOpen(bytes reason);
  event RebalanceCancelled();

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
    * @dev Rebalance vault by hedging or leveraging more
    * @param self Vault store data
    * @param rap GMXTypes.RebalanceAddParams
  **/
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

    if (rap.rebalanceType == GMXTypes.RebalanceType.Delta) {
      GMXChecks.beforeRebalanceDeltaChecks(self);
    } else if (rap.rebalanceType == GMXTypes.RebalanceType.Debt) {
      GMXChecks.beforeRebalanceDebtChecks(self);
    }

    self.status = GMXTypes.Status.Rebalance_Add;

    GMXManager.borrow(
      self,
      rap.borrowParams.borrowTokenAAmt,
      rap.borrowParams.borrowTokenBAmt
    );

    GMXTypes.AddLiquidityParams memory _alp;

    _alp.tokenAAmt = self.tokenA.balanceOf(address(this));
    _alp.tokenBAmt = self.tokenB.balanceOf(address(this));

    // Calculate deposit value after borrows and repays
    // Rebalance will only deal with tokenA and tokenB and not LP tokens
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
      rap.slippage
    );

    _alp.executionFee = rap.executionFee;

    _rc.depositKey = GMXManager.addLiquidity(
      self,
      _alp
    );

    self.rebalanceCache = _rc;
  }

  /**
    * @dev Process after rebalanceAdd()
    * @param self Vault store data
  **/
  function processRebalanceAdd(
    GMXTypes.Store storage self
  ) external {
    GMXChecks.beforeProcessRebalanceChecks(self);

    try GMXChecks.afterRebalanceChecks(self) {
      emit RebalanceSuccess(
        self.rebalanceCache.healthParams.svTokenValueBefore,
        GMXReader.svTokenValue(self)
      );

      self.status = GMXTypes.Status.Open;
    } catch (bytes memory reason) {
      self.status = GMXTypes.Status.Rebalance_Open;

      emit RebalanceOpen(reason);
    }
  }

  /**
    * @dev Process cancellation after rebalanceAdd()
    * @param self Vault store data
  **/
  function processRebalanceAddCancellation(
    GMXTypes.Store storage self
  ) external {
    GMXChecks.beforeProcessRebalanceChecks(self);

    GMXManager.repay(
      self,
      self.tokenA.balanceOf(address(this)),
      self.tokenB.balanceOf(address(this))
    );

    emit RebalanceCancelled();

    self.status = GMXTypes.Status.Open;
  }

  /**
    * @dev Rebalance vault by hedging or leveraging less
    * @param self Vault store data
    * @param rrp GMXTypes.RebalanceRemoveParams
  **/
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
    _rc.healthParams = _hp;

    self.rebalanceCache = _rc;

    if (rrp.rebalanceType == GMXTypes.RebalanceType.Delta) {
      GMXChecks.beforeRebalanceDeltaChecks(self);
    } else if (rrp.rebalanceType == GMXTypes.RebalanceType.Debt) {
      GMXChecks.beforeRebalanceDebtChecks(self);
    }

    self.status = GMXTypes.Status.Rebalance_Remove;

    GMXTypes.RemoveLiquidityParams memory _rlp;

    _rlp.lpAmt = rrp.lpAmtToRemove;

    // When rebalancing delta, repay only tokenA so withdraw liquidity only in tokenA
    // When rebalancing debt, repay only tokenB so withdraw liquidity only in tokenA
    if (rrp.rebalanceType == GMXTypes.RebalanceType.Delta) {
      address[] memory _tokenASwapPath = new address[](1);
      _tokenASwapPath[0] = address(self.lpToken);
      _rlp.tokenASwapPath = _tokenASwapPath;
    } else if (rrp.rebalanceType == GMXTypes.RebalanceType.Debt) {
      address[] memory _tokenBSwapPath = new address[](1);
      _tokenBSwapPath[0] = address(self.lpToken);
      _rlp.tokenBSwapPath = _tokenBSwapPath;
    }

    (
      _rlp.minTokenAAmt,
      _rlp.minTokenBAmt
    ) = GMXManager.calcMinTokensSlippageAmt(
      self,
      rrp.lpAmtToRemove,
      rrp.slippage
    );

    _rlp.executionFee = rrp.executionFee;

    _rc.withdrawKey = GMXManager.removeLiquidity(
      self,
      _rlp
    );

    self.rebalanceCache = _rc;
  }

  /**
    * @dev Process after rebalanceRemove()
    * @param self Vault store data
  **/
  function processRebalanceRemove(
    GMXTypes.Store storage self
  ) external {
    GMXChecks.beforeProcessRebalanceChecks(self);

    GMXManager.repay(
      self,
      self.tokenA.balanceOf(address(this)),
      self.tokenB.balanceOf(address(this))
    );

    try GMXChecks.afterRebalanceChecks(self) {
      emit RebalanceSuccess(
        self.rebalanceCache.healthParams.svTokenValueBefore,
        GMXReader.svTokenValue(self)
      );

      self.status = GMXTypes.Status.Open;
    } catch (bytes memory reason) {
      self.status = GMXTypes.Status.Rebalance_Open;

      emit RebalanceOpen(reason);
    }
  }

  /**
    * @dev Process cancellation after rebalanceRemove()
    * @param self Vault store data
  **/
  function processRebalanceRemoveCancellation(
    GMXTypes.Store storage self
  ) external {
    GMXChecks.beforeProcessRebalanceChecks(self);

    emit RebalanceCancelled();

    self.status = GMXTypes.Status.Open;
  }
}

