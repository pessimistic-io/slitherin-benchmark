//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

enum OptionsState {
    Settled,
    Active,
    Unlocked
}

enum EpochState {
    InActive,
    BootStrapped,
    Expired,
    Paused
}

enum Contracts {
    QuoteToken,
    BaseToken,
    FeeDistributor,
    FeeStrategy,
    OptionPricing,
    PriceOracle,
    VolatilityOracle,
    Gov
}

enum VaultConfig {
    IvBoost,
    BlackoutWindow,
    FundingInterval,
    BaseFundingRate,
    UseDiscount
}

