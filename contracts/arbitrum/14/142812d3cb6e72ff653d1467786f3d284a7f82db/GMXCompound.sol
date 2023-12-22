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
  uint256 public constant DUST_AMOUNT = 1e17;

  /* ========== EVENTS ========== */

  event Compound(address vault);

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
    GMXChecks.beforeCompoundChecks(self);

    self.refundee = payable(msg.sender);

    // TODO: Harvest rewards

    self.status = GMXTypes.Status.Compound;

    GMXTypes.CompoundCache memory _cc;
    _cc.compoundParams = cp;

    self.status = GMXTypes.Status.Compound_Swap;

    GMXManager.swap(self, _cc.compoundParams.swapParams);

    self.compoundCache = _cc;

    self.status = GMXTypes.Status.Compound_Add_Liquidity;

    processCompoundAdd(self);
  }

  /**
    * @dev Compound ERC20 token rewards, convert to more LP
    * @notice keeper will call compound with different ERC20 reward tokens received by vault
    * @param self Vault store data
  */
  function processCompoundAdd(
    GMXTypes.Store storage self
  ) public {
    GMXChecks.processCompoundAddChecks(self);

    GMXTypes.CompoundCache memory _cc = self.compoundCache;

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

    _alp.minMarketTokenAmt = GMXManager.calcMinMarketSlippageAmt(
      self,
      _cc.depositValue,
      _cc.compoundParams.depositParams.slippage
    );

    _alp.executionFee = _cc.compoundParams.depositParams.executionFee;

    bytes32 _depositKey = GMXManager.addLiquidity(
      self,
      _alp
    );

    _cc.depositKey = _depositKey;

    self.compoundCache = _cc;

    self.status = GMXTypes.Status.Compound_Liquidity_Added;
  }

  /**
    * @dev Compound ERC20 token rewards, convert to more LP
    * @notice keeper will call compound with different ERC20 reward tokens received by vault
    * @param self Vault store data
  */
  function processCompoundAdded(
    GMXTypes.Store storage self
  ) external {
    GMXChecks.processCompoundAddedChecks(self);

    emit Compound(address(this));

    self.refundee = payable(address(0));
    delete self.compoundCache;

    self.status = GMXTypes.Status.Open;
  }
}

