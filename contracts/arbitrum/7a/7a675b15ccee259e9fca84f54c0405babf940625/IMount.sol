// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

interface IMount {
    function updateReservesWallet(address newWallet) external;

    function excludeFromFees(address account, bool excluded) external;

    function stakeAmount(address account, uint256 amount) external;

    function setAutomatedMarketMakerPool(address pair, bool value) external;

    function isExcludedFromFees(address account) external view returns (bool);
}
