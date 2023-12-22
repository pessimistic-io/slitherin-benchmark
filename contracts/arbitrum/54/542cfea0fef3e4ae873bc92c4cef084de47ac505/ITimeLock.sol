// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// Timelock related data types
library TimeLockDataTypes {
  enum AgreementContext {
    TRADING_CORE,
    LIQUIDITY_POOL,
    FEE_VAULT
  }
}

interface ITimeLock {
  struct Agreement {
    uint256 amount;
    TimeLockDataTypes.AgreementContext agreementContext;
    bool isFrozen;
    address asset;
    address beneficiary;
    uint48 releaseTime;
  }

  function createAgreement(
    address asset,
    uint256 amount,
    address beneficiary,
    TimeLockDataTypes.AgreementContext agreementContext
  ) external;
}

