// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

struct InvestmentPart{
    address protocol;
    uint16 percentage;
}

struct InvestmentPartition{
    InvestmentPart[] parts;
    bool defined;
}



struct InvestmentAmountPart{
    address protocol;
    uint256 amount;
}

struct InvestmentAmountPartition{
    InvestmentAmountPart[] parts;
}
