// Contract that defines authority across the system and allows changes to it
// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./IDAOAuthority.sol";

contract DAOAuthority is IDAOAuthority {

    address public governor;
    address public policy;
    address public admin;
    address public forwarder;
    address public dispatcher;

    constructor(
        address _governor,
        address _policy,
        address _admin,
        address _forwarder,
        address _dispatcher
    ) {
        
        // Set the governor role
        governor = _governor;

        // Set the policy role
        policy = _policy;

        // Set the admin role
        admin = _admin;

        forwarder = _forwarder;

        dispatcher = _dispatcher;
        
    }

    function changeGovernor(address _newGovernor) external {
        require(msg.sender == governor, "UNAUTHORIZED");
        governor = _newGovernor;
        emit ChangedGovernor(governor);
    }

    function changePolicy(address _newPolicy) external {
        require(msg.sender == governor, "UNAUTHORIZED");
        policy = _newPolicy;
        emit ChangedPolicy(policy);
    }

    function changeAdmin(address _newAdmin) external {
        require(msg.sender == governor, "UNAUTHORIZED");
        admin = _newAdmin;
        emit ChangedAdmin(admin);
    }

    function changeForwarder(address _newForwarder) external {
        require(msg.sender == governor, "UNAUTHORIZED");
        forwarder = _newForwarder;
        emit ChangedForwarder(admin);
    }

    function changeDispatcher(address _dispatcher) external {
        require(msg.sender == governor, "UNAUTHORIZED");
        dispatcher = _dispatcher;
        emit ChangedDispatcher(dispatcher);
    }
}

