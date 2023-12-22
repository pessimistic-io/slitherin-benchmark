// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IDAOAuthority {

    /*********** EVENTS *************/
    event ChangedGovernor(address _newGovernor);
    event ChangedPolicy(address _newPolicy);
    event ChangedAdmin(address _newAdmin);
    event ChangedForwarder(address _newForwarder);
    event ChangedDispatcher(address _newDispatcher);

    struct Authorities {
        address governor;
        address policy;
        address admin;
        address forwarder;
        address dispatcher;
    }

    function getAuthorities() external view returns(Authorities memory);
}
