// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC20_IERC20.sol";
import "./SafeERC20.sol";

import "./IPSMRouter.sol";
import "./IPegStabilityModule.sol";

/// @title PSMRouter
/// @author Bluejay Core Team
/// @notice PSMRouter is a router for users to swap on PegStabilityModules
contract PSMRouter is IPSMRouter {
  using SafeERC20 for IERC20;

  // =============================== PUBLIC FUNCTIONS =================================

  /// @notice Swap exact number of input tokens to get minimum output tokens
  /// @param psm Address of the PegStabilityModule to perform swap on
  /// @param recipient Address to send output to
  /// @param toBluStablecoin If the swap direction is from external stablecoin to bluStable
  /// @param amountIn Amount of input tokens to swap
  /// @param amountOutMin Minimum amount of output tokens to receive
  function swapExactTokensForTokens(
    IPegStabilityModule psm,
    address recipient,
    bool toBluStablecoin,
    uint256 amountIn,
    uint256 amountOutMin
  ) public override {
    IERC20 tokenIn = toBluStablecoin
      ? psm.externalStablecoin()
      : psm.bluStablecoin();
    tokenIn.safeTransferFrom(msg.sender, address(psm), amountIn);
    uint256 amountOut = psm.swap(recipient, toBluStablecoin);
    require(amountOut >= amountOutMin, "Insufficient output");
  }

  /// @notice Swap maximum of input tokens to get exact number of output tokens
  /// @param psm Address of the PegStabilityModule to perform swap on
  /// @param recipient Address to send output to
  /// @param toBluStablecoin If the swap direction is from external stablecoin to bluStable
  /// @param amountOut Amount of output tokens to receive
  /// @param amountInMax Maximum amount of input tokens to swap
  function swapTokensForExactTokens(
    IPegStabilityModule psm,
    address recipient,
    bool toBluStablecoin,
    uint256 amountOut,
    uint256 amountInMax
  ) public override {
    uint256 amountIn = toBluStablecoin
      ? psm.getExternalStablecoinsIn(amountOut)
      : psm.getBluStablecoinsIn(amountOut);
    require(amountIn <= amountInMax, "Excessive input");
    swapExactTokensForTokens(
      psm,
      recipient,
      toBluStablecoin,
      amountIn,
      amountOut
    );
  }
}

