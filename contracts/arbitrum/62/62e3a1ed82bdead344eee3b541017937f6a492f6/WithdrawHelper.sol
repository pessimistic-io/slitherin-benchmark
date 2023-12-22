// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

import {IERC20Metadata as IERC20} from "./extensions_IERC20Metadata.sol";
import {IVault, IFlashLoanRecipient} from "./IFlashLoan.sol";
import {ICToken} from "./compound_ICToken.sol";
import {SafeMath} from "./SafeMath.sol";
import {PriceHelper} from "./PriceHelper.sol";
import {CTokenHelper} from "./CTokenHelper.sol";
import {GLPHelper} from "./CTokenHelper.sol";
import {PendingExecutor} from "./PendingExecutor.sol";
import {SwapProtector} from "./SwapProtector.sol";

contract WithdrawLoanHelper is PendingExecutor, SwapProtector {
  using PriceHelper for IERC20;
  using CTokenHelper for ICToken;
  using SafeMath for uint;

  IVault public vault;
  uint public withdrawFee;
  address payable public feeRecipient;

  function redeemAllMarkets(
    address account,
    ICToken redeemMarket,
    uint redeemAmount
  ) internal returns (IERC20 redeemedToken, uint redeemedAmount) {
    redeemedToken = redeemMarket.underlying();
    ICToken market = redeemMarket;
    uint balance = market.underlying().balanceOf(address(this));
    // use return value in case of rounding errors
    market.redeemForAccount(account, redeemAmount);

    redeemedAmount = market.underlying().balanceOf(
      address(this)
    ).sub(balance);

    return (redeemedToken, redeemedAmount);
  }

  function repayAllMarkets(
    address account,
    ICToken[] memory repayMarkets,
    uint[] memory repayAmounts
  ) internal {
    for(uint i=0; i < repayMarkets.length; i++) {
      ICToken market = repayMarkets[i];
      uint repayAmount = repayAmounts[i];
      CTokenHelper.approveMarket(market, repayAmount);
      market.repayForAccount(account, repayAmount);
    }
  }

  function getAmountIn(IERC20 tokenFrom, IERC20 tokenTo, uint amountOut) internal view returns (uint) {
    // add increase base loanedAmount by withdrawFee% (implies loanedAmount*withdrawFee > flashloanFee)
    uint amountToAfterFees = amountOut.mul(1e18+withdrawFee).div(1e18);
    // simulate a reverse swap + fees to get amount in
    // this entails that fees must cover the swap fees and the slippage (as well as flashloan fee)
    return tokenTo.getTokensForNumTokens(amountToAfterFees, tokenFrom);
  }

  function feeAndSwapRedeemed(
    IERC20 redeemedToken,
    uint redeemedAmount,
    IERC20[] memory loanTokens,
    uint[] memory loanAmounts,
    uint[] memory loanFees,
    uint24 maxSlippage
  ) internal returns (uint userBalance) {
    userBalance = redeemedAmount;

    for(uint i = 0; i < loanTokens.length; i++) {
      uint amountIn = getAmountIn(redeemedToken, loanTokens[i], loanAmounts[i]);
      require(userBalance > amountIn, "Not enough funds to swap");
      uint amountOut = swap(
        redeemedToken,
        loanTokens[i],
        amountIn,
        maxSlippage
      );
      userBalance -= amountIn;
      // must be > since protocol fee transfer will revert if exactly the same
      require(amountOut > loanAmounts[i]+loanFees[i], 'Not enough funds received to repay loan');
      uint protocolFee = amountOut.sub(loanAmounts[i]+loanFees[i]);
      // transfer fees here since we know we have enough to repay the loan after
      loanTokens[i].transfer(feeRecipient, protocolFee);
      // Transfer the loan + fees back to the vault
      loanTokens[i].transfer(address(vault), loanAmounts[i]+loanFees[i]);
      // subtract the traded tokens from the user balance
    }
  }

  // can only be called from within the flashloan callback
  function leveragedWithdraw(
    IERC20[] memory tokens,
    uint256[] memory amounts,
    uint256[] memory feeAmounts,
    WithdrawParams memory data
  ) internal {
    repayAllMarkets(
      data.account,
      data.repayMarkets,
      data.repayAmounts
    );

    (IERC20 redeemedToken, uint redeemedAmount) = redeemAllMarkets(
      data.account,
      data.redeemMarket,
      data.redeemAmount
    );

    uint userBalance = feeAndSwapRedeemed(
      redeemedToken,
      redeemedAmount,
      tokens,
      amounts,
      feeAmounts,
      data.maxSlippage
    );

    // transfer the remaining balance to the user
    GLPHelper.wrapTransfer(redeemedToken, data.account, userBalance);
  }
}

