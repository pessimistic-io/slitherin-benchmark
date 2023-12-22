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
    _rac.user = msg.sender; // should be approved keeper
    _rac.timestamp = block.timestamp;
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

    // TODO depositParams only allow for adding liquidity of 1 token, but we could ahve 2 tokens here that can be added..
    bytes32 _depositKey = GMXManager.addLiquidity(
      self,
      _rac.rebalanceAddParams.depositParams
    );

    _rac.depositKey = _depositKey;

    self.rebalanceAddCache = _rac;
  }

  /**
    * @dev Process after rebalancing by adding liquidity
    * @notice Called by keeper via Event Emitted from GMX
    * @param self Vault store data
    * @param depositKey Deposit key hash to find deposit info
  */
  function processRebalanceAdd(
    GMXTypes.Store storage self,
    bytes32 depositKey
  ) external {
    GMXChecks.processRebalanceAddChecks(self);

    GMXChecks.afterRebalanceAddChecks(self);

    GMXTypes.RebalanceAddCache memory _rac =
      self.rebalanceAddCache;

    _rac.healthParams.svTokenValueAfter = GMXReader.svTokenValue(self);

    // Refund any left over execution fees to keeper
    self.WNT.withdraw(self.WNT.balanceOf(address(this)));
    (bool success, ) = _rac.user.call{value: address(this).balance}("");
    require(success, "Transfer failed.");

    self.status = GMXTypes.Status.Open;

    delete self.rebalanceAddCache;

    emit Rebalance(
      _rac.healthParams.svTokenValueBefore,
      _rac.healthParams.svTokenValueAfter
    );
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
    _rrc.user = msg.sender; // should be approved keeper
    _rrc.timestamp = block.timestamp;
    _rrc.rebalanceRemoveParams = rrp;
    _rrc.healthParams = _hp;

    self.rebalanceRemoveCache = _rrc;

    GMXChecks.beforeRebalanceRemoveChecks(self);

    self.status = GMXTypes.Status.Rebalance_Remove_Remove_Liquidity;

    bytes32 _withdrawKey = GMXManager.removeLiquidity(
      self,
      _rrc.rebalanceRemoveParams.withdrawParams
    );

    _rrc.withdrawKey = _withdrawKey;

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
    * @param withdrawKey Withdraw key hash to find withdrawal info
  */
  function processRebalanceRemoveSwapForRepay(
    GMXTypes.Store storage self,
    bytes32 withdrawKey
  ) external {
    GMXChecks.processRebalanceRemoveSwapForRepayChecks(self, withdrawKey);

    GMXTypes.RebalanceRemoveCache memory _rrc =
      self.rebalanceRemoveCache;

    // Check if swap between assets are needed for repayment
    (
      bool _swapNeeded,
      address _tokenFrom,
      address _tokenTo,
      uint256 _tokenFromAmt
    ) = GMXManager.swapForRepay(
      self,
      _rrc.rebalanceRemoveParams.repayParams
    );

    _rrc.rebalanceRemoveParams.swapForRepayParams.tokenFrom = _tokenFrom;
    _rrc.rebalanceRemoveParams.swapForRepayParams.tokenTo = _tokenTo;
    _rrc.rebalanceRemoveParams.swapForRepayParams.tokenFromAmt = _tokenFromAmt;

    if (_swapNeeded) {
      // A swap is needed to repay tokens properly
      bytes32 _orderKey = GMXManager.swap(
        self,
        _rrc.rebalanceRemoveParams.swapForRepayParams
      );

      _rrc.rebalanceRemoveParams.swapForRepayParams.orderKey = _orderKey;

      self.rebalanceRemoveCache = _rrc;

      self.status = GMXTypes.Status.Rebalance_Remove_Repay;
    } else {
      // No swaps needed for repayment, we can proceed to repay immediately
      self.rebalanceRemoveCache = _rrc;

      self.status = GMXTypes.Status.Rebalance_Remove_Repay;

      processRebalanceRemoveRepay(self, withdrawKey, bytes32(0));
    }
  }

  /**
    * @dev Process repayments after swaps after rebalancing by removing liquidity
    * @notice Called by keeper via Event Emitted from GMX
    * @param self Vault store data
    * @param withdrawKey Withdraw key hash to find withdrawal info
    * @param orderKey Swap key hash to find withdrawKey hash
  */
  function processRebalanceRemoveRepay(
    GMXTypes.Store storage self,
    bytes32 withdrawKey,
    bytes32 orderKey
  ) public {
    GMXChecks.processRebalanceRemoveRepayChecks(self, withdrawKey, orderKey);

    GMXTypes.RebalanceRemoveCache memory _rrc =
      self.rebalanceRemoveCache;

    // Repay debt
    GMXManager.repay(
      self,
      _rrc.rebalanceRemoveParams.repayParams.repayTokenAAmt,
      _rrc.rebalanceRemoveParams.repayParams.repayTokenBAmt
    );

    self.status = GMXTypes.Status.Rebalance_Remove_Add_Liquidity;

    bytes32 _depositKey = GMXManager.addLiquidity(
      self,
      _rrc.rebalanceRemoveParams.depositParams
    );

    _rrc.depositKey = _depositKey;

    self.rebalanceRemoveCache = _rrc;
  }

  /**
    * @dev Process repayments after swaps after rebalancing by removing liquidity
    * @notice Called by keeper via Event Emitted from GMX
    * @param self Vault store data
    * @param depositKey Deposit key hash to find deposit info
  */
  function processRebalanceRemoveAddLiquidity(
    GMXTypes.Store storage self,
    bytes32 depositKey
  ) public {
    GMXChecks.processRebalanceRemoveAddLiquidityChecks(self, depositKey);

    GMXTypes.RebalanceRemoveCache memory _rrc =
      self.rebalanceRemoveCache;

    // Get state of vault after
    _rrc.healthParams.equityAfter = GMXReader.equityValue(self);
    _rrc.healthParams.svTokenValueAfter = GMXReader.svTokenValue(self);

    self.rebalanceRemoveCache = _rrc;

    GMXChecks.afterRebalanceRemoveChecks(self);

    // Refund any left over execution fees to keeper
    self.WNT.withdraw(self.WNT.balanceOf(address(this)));
    (bool success, ) = _rrc.user.call{value: address(this).balance}("");
    require(success, "Transfer failed.");

    self.status = GMXTypes.Status.Open;

    emit Rebalance(
      _rrc.healthParams.svTokenValueBefore,
      _rrc.healthParams.svTokenValueAfter
    );
  }
}

