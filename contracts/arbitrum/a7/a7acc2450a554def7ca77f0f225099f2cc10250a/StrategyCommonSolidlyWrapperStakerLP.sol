// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./StrategyCommonSolidlyStakerLP.sol";

contract StrategyCommonSolidlyWrapperStakerLP is StrategyCommonSolidlyStakerLP {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  // Adds liquidity to AMM and gets more LP tokens.
  function addLiquidity() internal override {
    uint256 outputBal = IERC20Upgradeable(output).balanceOf(address(this));
    uint256 lp0Amt = outputBal / 2;
    uint256 lp1Amt = outputBal - lp0Amt;

    (uint256 peg, ) = ISolidlyRouter(dystRouter).getAmountOut(lp0Amt, lpToken0, lpToken1);

    if (lp0Amt > peg) {
      IERC20Upgradeable(output).safeApprove(gaugeStaker, lp0Amt);
      IGaugeStaker(gaugeStaker).deposit(lp0Amt);
    } else {
      if (stable) {
        uint256 lp0Decimals = 10**IERC20Extended(lpToken0).decimals();
        uint256 lp1Decimals = 10**IERC20Extended(lpToken1).decimals();
        uint256 out0 = lpToken0 != output
          ? (ISolidlyRouter(dystRouter).getAmountsOut(lp0Amt, outputToLp0Route)[outputToLp0Route.length] * 1e18) /
            lp0Decimals
          : lp0Amt;
        uint256 out1 = lpToken1 != output
          ? (ISolidlyRouter(dystRouter).getAmountsOut(lp1Amt, outputToLp1Route)[outputToLp1Route.length] * 1e18) /
            lp1Decimals
          : lp0Amt;
        (uint256 amountA, uint256 amountB, ) = ISolidlyRouter(dystRouter).quoteAddLiquidity(
          lpToken0,
          lpToken1,
          stable,
          out0,
          out1
        );
        amountA = (amountA * 1e18) / lp0Decimals;
        amountB = (amountB * 1e18) / lp1Decimals;
        uint256 ratio = (((out0 * 1e18) / out1) * amountB) / amountA;
        lp0Amt = (outputBal * 1e18) / (ratio + 1e18);
        lp1Amt = outputBal - lp0Amt;
      }

      if (lpToken0 != output) {
        ISolidlyRouter(dystRouter).swapExactTokensForTokens(
          lp0Amt,
          0,
          outputToLp0Route,
          address(this),
          block.timestamp
        );
      }

      if (lpToken1 != output) {
        ISolidlyRouter(dystRouter).swapExactTokensForTokens(
          lp1Amt,
          0,
          outputToLp1Route,
          address(this),
          block.timestamp
        );
      }
    }

    uint256 lp0Bal = IERC20Upgradeable(lpToken0).balanceOf(address(this));
    uint256 lp1Bal = IERC20Upgradeable(lpToken1).balanceOf(address(this));
    ISolidlyRouter(dystRouter).addLiquidity(
      lpToken0,
      lpToken1,
      stable,
      lp0Bal,
      lp1Bal,
      1,
      1,
      address(this),
      block.timestamp
    );
  }
}

