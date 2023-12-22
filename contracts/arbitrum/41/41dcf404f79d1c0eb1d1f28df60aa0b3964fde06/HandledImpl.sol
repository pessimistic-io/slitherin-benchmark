// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

import {CErc20Delegate} from "./CErc20Delegate.sol";

contract HandledImpl is CErc20Delegate {
  // sync this from an external storage contract
  mapping(address => bool) public handlers;

  // make admin only
  function _setHandler(address handler, bool _isHandler) public {
    require(msg.sender == admin, "CErc20: Only admin");
    handlers[handler] = _isHandler;
  }

  function isHandler(address _addr) public view returns (bool) {
    return handlers[_addr];
  }

  function borrowForAccount(address account, uint256 borrowAmount)
    external
    virtual
    onlyHandler
    nonReentrant
    returns (uint256)
  {
    comptroller.addToMarketExternal(address(this), account);
    borrowForAccountInternal(account, borrowAmount);
    return NO_ERROR;
  }

  function borrowForAccountInternal(address account, uint256 borrowAmount) internal virtual {
    accrueInterest();
    uint256 allowed = comptroller.borrowAllowed(address(this), account, borrowAmount);
    if (allowed != 0) {
      revert BorrowComptrollerRejection(allowed);
    }
    if (accrualBlockNumber != getBlockNumber()) {
      revert BorrowFreshnessCheck();
    }

    /* Fail gracefully if protocol has insufficient underlying cash */
    if (getCashPrior() < borrowAmount) {
      revert BorrowCashNotAvailable();
    }

    uint256 accountBorrowsPrev = borrowBalanceStoredInternal(account);
    uint256 accountBorrowsNew = accountBorrowsPrev + borrowAmount;
    uint256 totalBorrowsNew = totalBorrows + borrowAmount;

    accountBorrows[account].principal = accountBorrowsNew;
    accountBorrows[account].interestIndex = borrowIndex;
    totalBorrows = totalBorrowsNew;

    doTransferOut(payable(msg.sender), borrowAmount); // transfer the tokens to the sender
    /* We emit a Borrow event */
    emit Borrow(account, borrowAmount, accountBorrowsNew, totalBorrowsNew);
  }

  // must allow reentry since intermediary collateral might overlap with final collateral
  // this is safe as long as all triggering handler methods are nonReentrant()
  function mintForAccount(address account, uint256 mintAmount)
    external
    virtual
    onlyHandler
    returns (uint256)
  {
    comptroller.addToMarketExternal(address(this), account);
    mintForAccountInternal(account, mintAmount);
    return NO_ERROR;
  }

  function mintForAccountInternal(address account, uint256 mintAmount) internal virtual {
    accrueInterest();
    if (autocompound) compoundFresh();
    /* Verify market's block number equals current block number */
    uint256 allowed = comptroller.mintAllowed(address(this), account, mintAmount);
    if (allowed != 0) {
      revert MintComptrollerRejection(allowed);
    }
    if (accrualBlockNumber != getBlockNumber() && !isGLP) {
      revert MintFreshnessCheck();
    }

    Exp memory exchangeRate = Exp({mantissa: exchangeRateStoredInternal()});
    // msg.sender is handler
    uint256 actualMintAmount = doTransferIn(msg.sender, mintAmount); //transfer from handler
    uint256 mintTokens = div_(actualMintAmount, exchangeRate);
    totalSupply = totalSupply + mintTokens;
    accountTokens[account] = accountTokens[account] + mintTokens; //apply changes to requester

    emit Mint(account, actualMintAmount, mintTokens);
    emit Transfer(address(0), account, mintTokens);
  }

  modifier onlyHandler() {
    require(isHandler(msg.sender), "CErc20: Only handler");
    _;
  }

  // must allow reentry since intermediary collateral might overlap with final collateral
  // this is safe as long as all triggering handler methods are nonReentrant()
  function redeemForAccount(address account, uint256 redeemTokens)
    external
    onlyHandler
    returns (uint256)
  {
    redeemForAccountFresh(payable(account), redeemTokens, 0);
    return NO_ERROR;
  }

  function redeemUnderlyingForAccount(address account, uint256 redeemAmount)
    external
    onlyHandler
    returns (uint256)
  {
    redeemForAccountFresh(payable(account), 0, redeemAmount);
    return NO_ERROR;
  }

  function redeemForAccountFresh(
    address payable redeemer,
    uint256 redeemTokensIn,
    uint256 redeemAmountIn
  ) internal {
    require(
      redeemTokensIn == 0 || redeemAmountIn == 0,
      "one of redeemTokensIn or redeemAmountIn must be zero"
    );
    accrueInterest();

    /* exchangeRate = invoke Exchange Rate Stored() */
    Exp memory exchangeRate = Exp({mantissa: exchangeRateStoredInternal()});

    uint256 redeemTokens;
    uint256 redeemAmount;
    /* If redeemTokensIn > 0: */
    if (redeemTokensIn > 0) {
      /*
      * We calculate the exchange rate and the amount of underlying to be redeemed:
      *  redeemTokens = redeemTokensIn
      *  redeemAmount = redeemTokensIn x exchangeRateCurrent
      */
      redeemTokens = redeemTokensIn;
      redeemAmount = mul_ScalarTruncate(exchangeRate, redeemTokensIn);
    } else {
      /*
      * We get the current exchange rate and calculate the amount to be redeemed:
      *  redeemTokens = redeemAmountIn / exchangeRate
      *  redeemAmount = redeemAmountIn
      */
      redeemTokens = div_(redeemAmountIn, exchangeRate);
      redeemAmount = redeemAmountIn;
    }

    /* Fail if redeem not allowed */
    uint256 allowed = comptroller.redeemAllowed(address(this), redeemer, redeemTokens);
    if (allowed != 0) {
      revert RedeemComptrollerRejection(allowed);
    }

    /* Verify market's block number equals current block number */
    if (accrualBlockNumber != getBlockNumber() && !isGLP) {
      revert RedeemFreshnessCheck();
    }

    /* Fail gracefully if protocol has insufficient cash */
    if (getCashPrior() < redeemAmount) {
      revert RedeemTransferOutNotPossible();
    }

    /////////////////////////
    // EFFECTS & INTERACTIONS
    // (No safe failures beyond this point)

    /*
    * We write the previously calculated values into storage.
    *  Note: Avoid token reentrancy attacks by writing reduced supply before external transfer.
      */
    totalSupply = totalSupply - redeemTokens;
    accountTokens[redeemer] = accountTokens[redeemer] - redeemTokens;

    /*
    * We invoke doTransferOut for the redeemer and the redeemAmount.
    *  Note: The cToken must handle variations between ERC-20 and ETH underlying.
      *  On success, the cToken has redeemAmount less of cash.
        *  doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
      */
    doTransferOut(payable(msg.sender), redeemAmount);

    /* We emit a Transfer event, and a Redeem event */
    emit Transfer(redeemer, address(this), redeemTokens);
    emit Redeem(redeemer, redeemAmount, redeemTokens);
    /* We call the defense hook */
    comptroller.redeemVerify(address(this), redeemer, redeemAmount, redeemTokens);
  }

  function repayForAccount(
    address borrower,
    uint repayAmount
  ) external virtual onlyHandler nonReentrant returns (uint256) {
    return repayForAccountInternal(borrower, repayAmount);
  }

  function repayForAccountInternal(address borrower, uint repayAmount) internal returns (uint) {
    accrueInterest();
    // repayBorrowFresh emits repay-borrow-specific logs on errors, so we don't need to
    return repayForAccountFresh(msg.sender, borrower, repayAmount);
  }

  /*
    the only difference between this and repayBorrowFresh is that the borrower is emitted as the repayer
    Since the leverage handler uses the user's own funds for everything, we want this for tracking accuracy
  */
  function repayForAccountFresh(address payer, address borrower, uint repayAmount) internal returns (uint) {
    /* Fail if repayBorrow not allowed */
    uint allowed = comptroller.repayBorrowAllowed(address(this), payer, borrower, repayAmount);
    if (allowed != 0) {
        revert RepayBorrowComptrollerRejection(allowed);
    }

    /* Verify market's block number equals current block number */
    if (accrualBlockNumber != getBlockNumber()) {
        revert RepayBorrowFreshnessCheck();
    }

    /* We fetch the amount the borrower owes, with accumulated interest */
    uint accountBorrowsPrev = borrowBalanceStoredInternal(borrower);

    /* If repayAmount == -1, repayAmount = accountBorrows */
    uint repayAmountFinal = repayAmount == type(uint).max ? accountBorrowsPrev : repayAmount;

    /////////////////////////
    // EFFECTS & INTERACTIONS
    // (No safe failures beyond this point)

    /*
     * We call doTransferIn for the payer and the repayAmount
     *  Note: The cToken must handle variations between ERC-20 and ETH underlying.
     *  On success, the cToken holds an additional repayAmount of cash.
     *  doTransferIn reverts if anything goes wrong, since we can't be sure if side effects occurred.
     *   it returns the amount actually transferred, in case of a fee.
     */
    uint actualRepayAmount = doTransferIn(payer, repayAmountFinal);

    /*
     * We calculate the new borrower and total borrow balances, failing on underflow:
     *  accountBorrowsNew = accountBorrows - actualRepayAmount
     *  totalBorrowsNew = totalBorrows - actualRepayAmount
     */
    uint accountBorrowsNew = accountBorrowsPrev - actualRepayAmount;
    uint totalBorrowsNew = totalBorrows - actualRepayAmount;

    /* We write the previously calculated values into storage */
    accountBorrows[borrower].principal = accountBorrowsNew;
    accountBorrows[borrower].interestIndex = borrowIndex;
    totalBorrows = totalBorrowsNew;

    /* We emit a RepayBorrow event */
    emit RepayBorrow(borrower, borrower, actualRepayAmount, accountBorrowsNew, totalBorrowsNew);

    return actualRepayAmount;
  }
}

