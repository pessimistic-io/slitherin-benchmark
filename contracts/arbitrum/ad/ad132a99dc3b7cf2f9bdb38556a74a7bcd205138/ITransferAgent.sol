// SPDX-License-Identifier: Business Source License 1.1
pragma solidity 0.8.18;

interface ITransferAgent {
    function adjustBalance(
        address account,
        uint256 currentBalance,
        uint256 newBalance,
        string memory memo
    ) external;

    function distributeDividends(
        address[] memory accounts,
        uint256 date,
        int256 rate,
        uint256 price
    ) external;

    function endOfDay(
        address[] memory accounts,
        uint256 date,
        int256 rate,
        uint256 price
    ) external;

    function settleTransactions(
        address[] memory accounts,
        uint256 date,
        uint256 price
    ) external;
}

