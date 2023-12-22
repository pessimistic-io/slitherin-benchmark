// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { GMXTypes } from "./GMXTypes.sol";
// import { GMXManager } from "./GMXManager.sol";

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
    * @param token Address of token to swap from
    * @param slippage Slippage tolerance for minimum amount to receive; e.g. 3 = 0.03%
    * @param deadline Timestamp of deadline for swap to go through
  */
  function compound(
    GMXTypes.Store storage self,
    address token,
    uint256 slippage,
    uint256 deadline
  ) external {
    // Convert reward token (typically GRAIL) to tokenB (typically ETH or USDC)
    // if (IERC20(token).balanceOf(address(this)) > DUST_AMOUNT) {
    //   GMXManager.compound(self, token, slippage, deadline);

    //   emit Compound(address(this));
    // }
  }
}

