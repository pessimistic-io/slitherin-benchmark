// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IPegStabilityModule.sol";

interface IPSMRouter {
  function swapExactTokensForTokens(
    IPegStabilityModule psm,
    address recipient,
    bool toBluStablecoin,
    uint256 amountIn,
    uint256 amountOutMin
  ) external;

  function swapTokensForExactTokens(
    IPegStabilityModule psm,
    address recipient,
    bool toBluStablecoin,
    uint256 amountOut,
    uint256 amountInMax
  ) external;
}

