// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// https://github.com/solidproof/projects/blob/19f3557b8ca067f33efe529018cb2e62773af967/MUX%20World/Contracts/aggregators/gmx/GmxAdapter.sol

interface IGLPAdapter {

    function muxAccountState() external view returns (AccountState memory);
}

struct AccountState {
    address account;
    uint256 cumulativeDebt;
    uint256 cumulativeFee;
    uint256 debtEntryFunding;
    address collateralToken;
    address indexToken;
    uint8 deprecated0;
    bool isLong;
    uint8 collateralDecimals;
    uint256 liquidationFee;
    bool isLiquidating;
    bytes32[18] reserved;
}
