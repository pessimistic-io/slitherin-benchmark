// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { GMXTypes } from "./GMXTypes.sol";
import { GMXReader } from "./GMXReader.sol";
import { GMXChecks } from "./GMXChecks.sol";
import { GMXManager } from "./GMXManager.sol";

library GMXRebalance {

  /* ========== EVENTS ========== */

  event Rebalance(uint256 svTokenValueBefore, uint256 svTokenValueAfter);

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
    * @dev Rebalance vault by adding liquidity
    * @param self Vault store data
    * @param rap GMXTypes.RebalanceAddParams struct
  **/
  function rebalanceAdd(
    GMXTypes.Store storage self,
    GMXTypes.RebalanceAddParams memory rap
  ) external {
    self.refundee = payable(msg.sender);

    GMXTypes.HealthParams memory _hp;
    _hp.lpAmtBefore = GMXReader.lpAmt(self);
    (
      _hp.debtAmtTokenABefore,
      _hp.debtAmtTokenBBefore
    ) = GMXReader.debtAmt(self);
    _hp.debtRatioBefore = GMXReader.debtRatio(self);
    _hp.deltaBefore = GMXReader.delta(self);
    _hp.svTokenValueBefore = GMXReader.svTokenValue(self);

    GMXTypes.RebalanceAddCache memory _rac;
    _rac.rebalanceAddParams = rap;
    _rac.healthParams = _hp;

    self.rebalanceAddCache = _rac;

    GMXChecks.beforeRebalanceAddChecks(self);

    self.status = GMXTypes.Status.Rebalance_Add;

    self.status = GMXTypes.Status.Rebalance_Add_Borrow;

    GMXManager.borrow(
      self,
      _rac.rebalanceAddParams.borrowParams.borrowTokenAAmt,
      _rac.rebalanceAddParams.borrowParams.borrowTokenBAmt
    );

    self.status = GMXTypes.Status.Rebalance_Add_Repay;

    GMXManager.repay(
      self,
      _rac.rebalanceAddParams.repayParams.repayTokenAAmt,
      _rac.rebalanceAddParams.repayParams.repayTokenBAmt
    );

    self.status = GMXTypes.Status.Rebalance_Add_Add_Liquidity;

    GMXTypes.AddLiquidityParams memory _alp;
    _alp.tokenAAmt = self.tokenA.balanceOf(address(this));
    _alp.tokenBAmt = self.tokenB.balanceOf(address(this));

    // Calculate deposit value after borrows and repays
    // Note that rebalance will only deal with tokenA and tokenB
    _rac.depositValue = GMXReader.convertToUsdValue(
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
      _rac.depositValue,
      rap.depositParams.slippage
    );

    _alp.executionFee = _rac.rebalanceAddParams.depositParams.executionFee;

    _rac.depositKey = GMXManager.addLiquidity(
      self,
      _alp
    );

    self.rebalanceAddCache = _rac;
  }

  /**
    * @dev Process after rebalancing by adding liquidity
    * @notice Called by keeper via Event Emitted from GMX
    * @param self Vault store data
  */
  function processRebalanceAdd(
    GMXTypes.Store storage self
  ) external {
    GMXChecks.processRebalanceAddChecks(self);

    GMXChecks.afterRebalanceAddChecks(self);

    GMXTypes.RebalanceAddCache memory _rac =
      self.rebalanceAddCache;

    _rac.healthParams.svTokenValueAfter = GMXReader.svTokenValue(self);

    emit Rebalance(
      _rac.healthParams.svTokenValueBefore,
      _rac.healthParams.svTokenValueAfter
    );

    self.status = GMXTypes.Status.Open;
  }

  /**
    * @dev Rebalance vault by removing liquidity
    * @param self Vault store data
    * @param rrp GMXTypes.RebalanceRemoveParams struct
  **/
  function rebalanceRemove(
    GMXTypes.Store storage self,
    GMXTypes.RebalanceRemoveParams memory rrp
  ) external {
    GMXTypes.HealthParams memory _hp;
    _hp.lpAmtBefore = GMXReader.lpAmt(self);
    (
      _hp.debtAmtTokenABefore,
      _hp.debtAmtTokenBBefore
    ) = GMXReader.debtAmt(self);
    _hp.debtRatioBefore = GMXReader.debtRatio(self);
    _hp.deltaBefore = GMXReader.delta(self);
    _hp.svTokenValueBefore = GMXReader.svTokenValue(self);

    GMXTypes.RebalanceRemoveCache memory _rrc;
    _rrc.rebalanceRemoveParams = rrp;
    _rrc.healthParams = _hp;

    self.rebalanceRemoveCache = _rrc;

    self.refundee = payable(msg.sender);

    GMXChecks.beforeRebalanceRemoveChecks(self);

    self.status = GMXTypes.Status.Rebalance_Remove_Remove_Liquidity;

    GMXTypes.RemoveLiquidityParams memory _rlp;
    _rlp.lpAmt = _rrc.rebalanceRemoveParams.lpAmt;

    (
      _rlp.minTokenAAmt,
      _rlp.minTokenBAmt
    ) = GMXManager.calcMinTokensSlippageAmt(
      self,
      _rrc.rebalanceRemoveParams.lpAmt,
      _rrc.rebalanceRemoveParams.withdrawParams.slippage
    );

    _rlp.executionFee = _rrc.rebalanceRemoveParams.withdrawParams.executionFee;
    // Long strategy to receive tokenB only
    if (self.delta == GMXTypes.Delta.Long) {
      _rlp.tokenASwapPath = new address[](1);
      _rlp.tokenASwapPath[0] = address(self.lpToken);
    }

    _rrc.withdrawKey = GMXManager.removeLiquidity(
      self,
      _rlp
    );

    self.rebalanceRemoveCache = _rrc;

    self.status = GMXTypes.Status.Rebalance_Remove_Borrow;

    GMXManager.borrow(
      self,
      _rrc.rebalanceRemoveParams.borrowParams.borrowTokenAAmt,
      _rrc.rebalanceRemoveParams.borrowParams.borrowTokenBAmt
    );

    self.status = GMXTypes.Status.Rebalance_Remove_Swap_For_Repay;
  }

  /**
    * @dev Process after rebalancing by removing liquidity; checking if swap needed
    * @notice Called by keeper via Event Emitted from GMX
    * @param self Vault store data
  */
  function processRebalanceRemoveSwapForRepay(
    GMXTypes.Store storage self
  ) external {
    GMXChecks.processRebalanceRemoveSwapForRepayChecks(self);

    GMXTypes.RebalanceRemoveCache memory _rrc =
      self.rebalanceRemoveCache;

    // Check if swap between assets are needed for repayment
    (
      bool _swapNeeded,
      address _tokenFrom,
      address _tokenTo,
      uint256 _tokenFromAmt
    ) = GMXManager.calcSwapForRepay(
      self,
      _rrc.rebalanceRemoveParams.repayParams
    );

    if (_swapNeeded) {
      _rrc.rebalanceRemoveParams.swapParams.tokenIn = _tokenFrom;
      _rrc.rebalanceRemoveParams.swapParams.tokenOut = _tokenTo;
      _rrc.rebalanceRemoveParams.swapParams.amountIn = _tokenFromAmt;

      GMXManager.swap(self, _rrc.rebalanceRemoveParams.swapParams);
    }

    self.rebalanceRemoveCache = _rrc;

    self.status = GMXTypes.Status.Rebalance_Remove_Repay;

    processRebalanceRemoveRepay(self);
  }

  /**
    * @dev Process repayments after swaps after rebalancing by removing liquidity
    * @notice Called by keeper via Event Emitted from GMX
    * @param self Vault store data
  */
  function processRebalanceRemoveRepay(
    GMXTypes.Store storage self
  ) public {
    GMXChecks.processRebalanceRemoveRepayChecks(self);

    GMXTypes.RebalanceRemoveCache memory _rrc =
      self.rebalanceRemoveCache;

    // Repay debt
    GMXManager.repay(
      self,
      _rrc.rebalanceRemoveParams.repayParams.repayTokenAAmt,
      _rrc.rebalanceRemoveParams.repayParams.repayTokenBAmt
    );

    self.status = GMXTypes.Status.Rebalance_Remove_Add_Liquidity;

    GMXTypes.AddLiquidityParams memory _alp;
    _alp.tokenAAmt = self.tokenA.balanceOf(address(this));
    _alp.tokenBAmt = self.tokenB.balanceOf(address(this));

    // Calculate deposit value after borrows and repays
    // Note that rebalance will only deal with tokenA and tokenB
    _rrc.depositValue = GMXReader.convertToUsdValue(
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
      _rrc.depositValue,
      _rrc.rebalanceRemoveParams.depositParams.slippage
    );

    _alp.executionFee = _rrc.rebalanceRemoveParams.depositParams.executionFee;

    _rrc.depositKey = GMXManager.addLiquidity(
      self,
      _alp
    );

    self.rebalanceRemoveCache = _rrc;
  }

  /**
    * @dev Process repayments after swaps after rebalancing by removing liquidity
    * @notice Called by keeper via Event Emitted from GMX
    * @param self Vault store data
  */
  function processRebalanceRemoveAddLiquidity(
    GMXTypes.Store storage self
  ) public {
    GMXChecks.processRebalanceRemoveAddLiquidityChecks(self);

    GMXTypes.RebalanceRemoveCache memory _rrc =
      self.rebalanceRemoveCache;

    // Get state of vault after
    _rrc.healthParams.equityAfter = GMXReader.equityValue(self);
    _rrc.healthParams.svTokenValueAfter = GMXReader.svTokenValue(self);

    self.rebalanceRemoveCache = _rrc;

    GMXChecks.afterRebalanceRemoveChecks(self);

    emit Rebalance(
      _rrc.healthParams.svTokenValueBefore,
      _rrc.healthParams.svTokenValueAfter
    );

    self.status = GMXTypes.Status.Open;
  }
}

