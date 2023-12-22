// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "./TrustNetworkV0.sol";

/**
 * Encapsulated network of wallets that have already established trust between
 * each other.
 */
contract TrustNetwork is TrustNetworkV0 {
    /**
     * Status of a connection between two parties. It's important to note that
     * status of the connection is directional. If A requests connection to B,
     * the status of the A -> B connection is "Initiated" whereas the status of
     * the B -> A connection is "PendingApproval".
     */
    enum Status {
        // Unknown value, representing unset status
        Unknown,
        // The connection has been initiated by the caller
        Initiated,
        // The connection is awaiting approval by the caller
        PendingApproval,
        // The connection is established
        Established
    }

    /**
     * Represents information about a connection between a caller parties and a
     * counterparty.
     */
    struct ConnectionInfo {
        address Counterparty;
        Status Status;
    }

    mapping(address => address[]) private connections;
    mapping(address => mapping(address => Status)) private connectionStatuses;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * Called after an upgrade. Typical initialize method is not called during upgrade.
     */
    function initializeAfterUpgrade() public reinitializer(2) {}

    /**
     * Initiates a connection between transaction sender and the specified
     * counterparty. If the connections exists already nothing is modified and
     * no error is thrown, i.e. the method is immutable.
     */
    function initiateConnection(address counterparty) public {
        if (msg.sender == counterparty) {
            revert("Approver cannot have the same address as the initiator");
        }

        if (areConnected(msg.sender, counterparty)) return;
        if (connectionStatuses[msg.sender][counterparty] == Status.Initiated)
            return;

        // If, by chance, the counterparty also wanted to initiate, let's just
        // approve it.
        if (connectionStatuses[counterparty][msg.sender] == Status.Initiated) {
            approveConnection(counterparty);
            return;
        }

        connectionStatuses[msg.sender][counterparty] = Status.Initiated;
        connectionStatuses[counterparty][msg.sender] = Status.PendingApproval;
        connections[msg.sender].push(counterparty);
        connections[counterparty].push(msg.sender);
    }

    /**
     * Approves a connection between transaction sender and the specified
     * counterparty. If the connections exists already nothing is modified and
     * no error is thrown, i.e. the method is immutable.
     */
    function approveConnection(address counterparty) public {
        if (areConnected(msg.sender, counterparty)) return;

        require(
            connectionStatuses[counterparty][msg.sender] == Status.Initiated,
            "The counterparty hasn't initiated the connection yet"
        );
        assert(
            connectionStatuses[msg.sender][counterparty] ==
                Status.PendingApproval
        );

        connectionStatuses[msg.sender][counterparty] = Status.Established;
        connectionStatuses[counterparty][msg.sender] = Status.Established;
    }

    /**
     * Checks whether or not a trust connection between the two parties has been
     * established.
     */
    function areConnected(
        address party1,
        address party2
    ) public view returns (bool) {
        return connectionStatuses[party1][party2] == Status.Established;
    }

    /**
     * Gets all existing connections for the specified party.
     */
    function getConnections(
        address party
    ) public view returns (ConnectionInfo[] memory) {
        ConnectionInfo[] memory result = new ConnectionInfo[](
            connections[party].length
        );

        for (uint256 i = 0; i < connections[party].length; ++i) {
            address counterparty = connections[party][i];
            result[i] = ConnectionInfo(
                counterparty,
                connectionStatuses[party][counterparty]
            );
        }

        return result;
    }

    /**
     * Deletes specified connection. Does nothing if the connection doesn't
     * exist.
     * The connection may be in any state.
     */
    function deleteConnection(address counterparty) public {
        if (msg.sender == counterparty) {
            revert(
                "Counterparty cannot have the same address as the initiator"
            );
        }

        delete connectionStatuses[msg.sender][counterparty];
        delete connectionStatuses[counterparty][msg.sender];

        address[] storage userConnections = connections[msg.sender];
        for (uint256 i = 0; i < userConnections.length; ++i) {
            if (userConnections[i] == counterparty) {
                if (userConnections.length > 1) {
                    userConnections[i] = userConnections[
                        userConnections.length - 1
                    ];
                }
                userConnections.pop();
            }
        }

        userConnections = connections[counterparty];
        for (uint256 i = 0; i < userConnections.length; ++i) {
            if (userConnections[i] == msg.sender) {
                if (userConnections.length > 1) {
                    userConnections[i] = userConnections[
                        userConnections.length - 1
                    ];
                }
                userConnections.pop();
            }
        }
    }
}

