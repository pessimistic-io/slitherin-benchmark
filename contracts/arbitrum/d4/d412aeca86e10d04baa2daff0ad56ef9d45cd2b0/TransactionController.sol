// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "./IERC20.sol";

import "./BarqAwards.sol";
import "./TrustNetwork.sol";

import "./TransactionControllerV0.sol";

/**
 * A smart contract aggregating all transactions happening in the barq universe.
 */
contract TransactionController is TransactionControllerV0 {
    enum Status {
        // 0 = Unknown value, representing unset status
        Unknown,
        // 1 = The transaction has been initiated by the recipient
        Initiated,
        // 2 = The transaction has been finalized
        Finalized
    }

    /**
     * A record listing details of a single transaction.
     */
    struct TransactionInfo {
        address Sender;
        address Recipient;
        uint256 Value;
        IERC20 Token;
        Status Status;
    }

    // A registry of barq awards (claims to the barq token) presented by this
    // transactions controller per each transaction.
    BarqAwards private awards;

    // A network of tunnels between parties:
    TrustNetwork private tunnels;

    // An array with all transactions:
    TransactionInfo[] private transactions;

    // Indexes of all transactions where an address is either a sender or
    // a recipient:
    mapping(address => uint256[]) transactionIndexes;

    // Index of the latest transaction between two parties:
    mapping(address => mapping(address => uint256)) latestTransactionIndexes;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * Called after an upgrade. Typicall initialize method is not called during upgrade.
     * Deploys a controller, injecting trust network used to verify tunnels
     * between parties, and a register of barq awards.
     */
    function initializeAfterUpgrade(
        TrustNetwork trustNetwork,
        BarqAwards barqAwards
    ) public reinitializer(2) {
        tunnels = trustNetwork;
        awards = barqAwards;

        // Initialize the 0th element of the array to a null object:
        transactions.push(
            TransactionInfo(
                address(0),
                address(0),
                0,
                IERC20(address(0)),
                Status.Unknown
            )
        );
    }

    /**
     * Get all transactions for which the specified party was a party (either
     * sender or a recipient).
     */
    function getTransactions(
        address party
    ) public view returns (TransactionInfo[] memory) {
        uint256[] memory indexes = transactionIndexes[party];
        TransactionInfo[] memory result = new TransactionInfo[](indexes.length);
        for (uint256 i = 0; i < indexes.length; ++i) {
            result[i] = transactions[indexes[i]];
        }
        return result;
    }

    /**
     * Provided that a trust tunnel exists, initiates a transaction between the
     * caller and the specified sender, i.e. a request to send the money by the
     * sender to the caller of this method.
     */
    function initiateTransfer(
        address sender,
        uint256 value,
        IERC20 token
    ) public {
        // Sender of the request is the recipient of the money, so let's just
        // label him/her as such to avoid confusion:
        address recipient = msg.sender;

        if (!tunnels.areConnected(sender, recipient)) {
            revert("There's no trust in this world");
        }

        if (hasTransactionInProgress(sender, recipient)) {
            revert("An unfinalized transaction already exists");
        }

        TransactionInfo memory info = TransactionInfo(
            sender,
            recipient,
            value,
            token,
            Status.Initiated
        );
        appendLatestTransaction(sender, recipient, info);
    }

    /**
     * Provided that a trust tunnel exists, transfers funds between the
     * caller and the recipient, marking the transaction as Finalzied.
     */
    function transferFunds(
        address recipient,
        uint256 value,
        IERC20 token
    ) public {
        if (!tunnels.areConnected(msg.sender, recipient)) {
            revert("There's no trust in this world");
        }

        TransactionInfo storage latestTransaction = getLatestTransaction(
            msg.sender,
            recipient
        );

        if (latestTransaction.Status != Status.Initiated) {
            // Latest transaction was either finalized or unknown (which
            // indicates no previous transactions), so we are appending the next
            // one:
            TransactionInfo memory info = TransactionInfo(
                msg.sender,
                recipient,
                value,
                token,
                Status.Finalized
            );

            appendLatestTransaction(msg.sender, recipient, info);

            // Award a claims to the token to both parties:
            awards.awardDefaultAmountTo([msg.sender, recipient]);

            if (!token.transferFrom(msg.sender, recipient, value)) {
                revert("Cannot transfer tokens between parties");
            }
        } else if (
            latestTransaction.Status == Status.Initiated &&
            latestTransaction.Value == value &&
            latestTransaction.Token == token &&
            latestTransaction.Sender == msg.sender
        ) {
            assert(latestTransaction.Recipient == recipient);
            // Latest transaction is in progress and we can finalize it now:
            latestTransaction.Status = Status.Finalized;

            // Award a claims to the token to both parties:
            awards.awardDefaultAmountTo([msg.sender, recipient]);

            if (!token.transferFrom(msg.sender, recipient, value)) {
                revert("Cannot transfer tokens between parties");
            }
        } else {
            // Someone tried to finalized an initialized transaction with a different
            // amount (or send money in the opposite direction):
            revert("Cannot finalize with a mismatching transfer");
        }
    }

    function appendLatestTransaction(
        address sender,
        address recipient,
        TransactionInfo memory info
    ) private {
        assert(
            info.Status == Status.Initiated || info.Status == Status.Finalized
        );

        uint256 currentIndex = transactions.length;
        // We initialized the transactions array with a null object at the 0th
        // index so the current index cannot be 0:
        assert(currentIndex > 0);

        transactions.push(info);
        transactionIndexes[sender].push(currentIndex);
        transactionIndexes[recipient].push(currentIndex);
        latestTransactionIndexes[sender][recipient] = currentIndex;
        latestTransactionIndexes[recipient][sender] = currentIndex;
    }

    function getLatestTransaction(
        address sender,
        address recipient
    ) private view returns (TransactionInfo storage) {
        uint256 index = latestTransactionIndexes[sender][recipient];
        assert(latestTransactionIndexes[recipient][sender] == index);
        // Mapping returns 0 if not present and we've put a null object at 0th
        // index of the transactions array, so that it works nicely.
        return transactions[index];
    }

    function hasTransactionInProgress(
        address sender,
        address recipient
    ) private view returns (bool) {
        return
            getLatestTransaction(sender, recipient).Status == Status.Initiated;
    }
}

