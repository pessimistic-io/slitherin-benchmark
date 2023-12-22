// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { GMXTypes } from "./GMXTypes.sol";
import { GMXChecks } from "./GMXChecks.sol";
import { GMXManager } from "./GMXManager.sol";
import { GMXReader } from "./GMXReader.sol";

library GMXCompound {
  using SafeERC20 for IERC20;

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;

  /* ========== EVENTS ========== */

  event Compound();
  event CompoundCancelled();

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
    * @dev Compound ERC20 token rewards, convert to more LP
    * @notice keeper will call compound with different ERC20 reward tokens received by vault
    * @param self Vault store data
    * @param cp GMXTypes.CompoundParams
  */
  function compound(
    GMXTypes.Store storage self,
    GMXTypes.CompoundParams memory cp
  ) external {
    self.refundee = payable(msg.sender);

    // TODO: Harvest rewards by claiming, or if it's airdropped we can just recompound

    GMXTypes.CompoundCache memory _cc;
    _cc.compoundParams = cp;

    GMXManager.swapExactTokensForTokens(self, _cc.compoundParams.swapParams);

    GMXTypes.AddLiquidityParams memory _alp;
    _alp.tokenAAmt = self.tokenA.balanceOf(address(this));
    _alp.tokenBAmt = self.tokenB.balanceOf(address(this));

    _cc.depositValue = GMXReader.convertToUsdValue(
      self,
      address(self.tokenA),
      self.tokenA.balanceOf(address(this))
    )
    + GMXReader.convertToUsdValue(
      self,
      address(self.tokenB),
      self.tokenB.balanceOf(address(this))
    );

    self.compoundCache = _cc;

    GMXChecks.beforeCompoundChecks(self);

    self.status = GMXTypes.Status.Compound;

    _alp.minMarketTokenAmt = GMXManager.calcMinMarketSlippageAmt(
      self,
      _cc.depositValue,
      _cc.compoundParams.depositParams.slippage
    );

    _alp.executionFee = _cc.compoundParams.depositParams.executionFee;

    _cc.depositKey = GMXManager.addLiquidity(
      self,
      _alp
    );
  }

  /**
    * @dev Compound ERC20 token rewards, convert to more LP
    * @notice keeper will call compound with different ERC20 reward tokens received by vault
    * @param self Vault store data
  */
  function processCompound(
    GMXTypes.Store storage self
  ) external {
    GMXChecks.beforeProcessCompoundChecks(self);

    emit Compound();

    self.status = GMXTypes.Status.Open;
  }

  /**
    * @dev Compound ERC20 token rewards, convert to more LP
    * @notice keeper will call compound with different ERC20 reward tokens received by vault
    * @param self Vault store data
  */
  function processCompoundCancellation(
    GMXTypes.Store storage self
  ) external {
    GMXChecks.beforeProcessCompoundCancellationChecks(self);

    emit CompoundCancelled();

    self.status = GMXTypes.Status.Open;
  }
}

