// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IInvoice {
    struct InvoiceCore {
        uint256 amount;
        address unitOfAccount;
        uint256 expirationBlock;
        string description;
        address[] whitelist;
    }
    struct InvoiceInfo {
        InvoiceCore core;
        uint256 invoiceId;
        address createdBy;
        bool isPaid;
        bool isCanceled;
    }

    enum InvoiceState {
        None,
        Active,
        Paid,
        Expired,
        Canceled
    }

    function createInvoice(address pool, InvoiceCore memory core) external;

    function payInvoice(address pool, uint256 invoiceId) external payable;

    function cancelInvoice(address pool, uint256 invoiceId) external;

    function setInvoiceCanceled(address pool, uint256 invoiceId) external;
}

