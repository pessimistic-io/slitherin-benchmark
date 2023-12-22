// SPDX-License-Identifier: Business Source License 1.1
pragma solidity 0.8.18;

import {IAuthorization} from "./IAuthorization.sol";

interface ITransactionStorage {
    enum TransactionType {
        INVALID,
        ADJUSTMENT,
        AIP,
        DIVIDEND,
        DIVIDEND_REINVESTMENT,
        CASH_LIQUIDATION,
        SHARE_LIQUIDATION,
        CASH_PURCHASE,
        SHARE_PURCHASE,
        FULL_LIQUIDATION
    }

    struct TransactionDetail {
        TransactionType txType;
        uint256 date;
        uint256 amount;
        bool selfService;
    }

    struct ShareholderTransaction {
        bytes32 txId;
        TransactionDetail txDetail;
    }

    function clearTransactionStorage(
        address account,
        bytes32 requestId
    ) external returns (bool);

    function unlistFromAccountsWithPendingTransactions(
        address account
    ) external;

    function getAccountTransactions(
        address account
    ) external view returns (bytes32[] memory);

    function getTransactionDetail(
        bytes32 requestId
    ) external view returns (uint8, uint256, uint256, bool);

    function getAccountsWithTransactions(
        uint256 pageSize
    ) external view returns (address[] memory accounts);

    function getAccountsWithTransactionsCount() external view returns (uint256);

    function hasTransactions(address account) external view returns (bool);

    function isFromAccount(
        address account,
        bytes32 requestId
    ) external view returns (bool);
}

interface IShareholderTransaction {
    function requestCashPurchase(
        address account,
        uint256 date,
        uint256 amount
    ) external;

    function requestCashLiquidation(
        address account,
        uint256 date,
        uint256 amount
    ) external;

    function requestFullLiquidation(address account, uint256 date) external;
}

interface IShareholderSelfServiceTransaction {
    function requestSelfServiceCashPurchase(uint256 amount) external;

    function requestSelfServiceCashLiquidation(uint256 amount) external;

    function requestSelfServiceFullLiquidation() external;

    function enableSelfService() external;

    function disableSelfService() external;

    function isSelfServiceEnabled() external view returns (bool);
}

interface ITransferAgentTransaction {
    function setupAIP(address account, uint256 date, uint256 amount) external;
}

interface ICancellableSelfServiceTransaction {
    function cancelSelfServiceRequest(
        bytes32 requestId,
        string memory memo
    ) external;
}

interface ICancellableTransaction {
    function cancelRequest(
        address account,
        bytes32 requestId,
        string calldata memo
    ) external;
}

