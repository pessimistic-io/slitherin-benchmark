// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { GMXTypes } from "./GMXTypes.sol";
import { GMXChecks } from "./GMXChecks.sol";
import { GMXManager } from "./GMXManager.sol";

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

    self.status = GMXTypes.Status.Compound;

    GMXTypes.CompoundCache memory _cc;
    _cc.user = payable(msg.sender);
    _cc.timestamp = block.timestamp;
    _cc.compoundParams = cp;

    self.refundTo = payable(msg.sender);

    GMXTypes.SwapParams memory _sp = _cc.compoundParams.swapParams;

    // Convert reward token to tokenB (typically ETH or USDC)
    if (IERC20(_sp.tokenFrom).balanceOf(address(this)) > DUST_AMOUNT) {
      if (
        _sp.tokenFrom != address(self.tokenA) &&
        _sp.tokenFrom != address(self.tokenB)
      ) {
        // Swap token to one of the tokens in LP
        self.status = GMXTypes.Status.Compound_Swap;

        bytes32 _orderKey = GMXManager.swap(
          self,
          _sp
        );

        _cc.compoundParams.swapParams.orderKey = _orderKey;

        self.compoundCache = _cc;

        self.status = GMXTypes.Status.Compound_Add_Liquidity;
      } else if (
        _sp.tokenFrom != address(self.tokenA) ||
        _sp.tokenFrom != address(self.tokenB)
      ) {
        self.compoundCache = _cc;

        self.status = GMXTypes.Status.Compound_Add_Liquidity;

        processCompoundAdd(self, bytes32(0));
      }
    }
  }

  /**
    * @dev Compound ERC20 token rewards, convert to more LP
    * @notice keeper will call compound with different ERC20 reward tokens received by vault
    * @param self Vault store data
    * @param orderKey Order key
  */
  function processCompoundAdd(
    GMXTypes.Store storage self,
    bytes32 orderKey
  ) public {
    GMXChecks.processCompoundAddChecks(self, orderKey);

    GMXTypes.CompoundCache memory _cc = self.compoundCache;

    bytes32 _depositKey = GMXManager.addLiquidity(
      self,
      _cc.compoundParams.depositParams
    );

    _cc.depositKey = _depositKey;

    self.compoundCache = _cc;

    self.status = GMXTypes.Status.Compound_Liquidity_Added;
  }

  /**
    * @dev Compound ERC20 token rewards, convert to more LP
    * @notice keeper will call compound with different ERC20 reward tokens received by vault
    * @param self Vault store data
    * @param depositKey Deposit key
  */
  function processCompoundAdded(
    GMXTypes.Store storage self,
    bytes32 depositKey
  ) external {
    GMXChecks.processCompoundAddedChecks(self, depositKey);

    self.status = GMXTypes.Status.Open;

    emit Compound(address(this));
  }
}

