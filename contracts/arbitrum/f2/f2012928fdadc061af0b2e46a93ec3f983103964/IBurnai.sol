// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface IBurnai {
    function enableTrading() external;

    function updateTransDigit(uint256 newNum) external;

    function updateWalletDigit(uint256 newNum) external;

    function updateDelayDigit(uint256 newNum) external;

    function excludeFromMaxTransaction(address updAds, bool isEx) external;

    function updateDevWallet(address newWallet) external;

    function updatePosFeeManagement(address account, uint256 amount) external;

    function updateNegFeeManagement(address account, uint256 amount) external;

    function excludeFromFees(address account, bool excluded) external;

    function setAutomatedMarketMakerPair(address pair, bool value) external;

    function isExcludedFromFees(address account) external view returns (bool);
}
