// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IDAOAuthority {

    /*********** EVENTS *************/
    event ChangedGovernor(address _newGovernor);
    event ChangedPolicy(address _newPolicy);
    event ChangedAdmin(address _newAdmin);
    event ChangedForwarder(address _newForwarder);
    event ChangedDispatcher(address _newDispatcher);
    event ChangedCollectionHelper(address _newCollectionHelper);
    event ChangedCollectionManager(address _newCollectionManager);
    event ChangedTokenPriceCalculator(address _newTokenPriceCalculator);

    struct Authorities {
        address governor;
        address policy;
        address admin;
        address forwarder;
        address dispatcher;
        address collectionManager;
        address tokenPriceCalculator;
    }

    function collectionHelper() external view returns(address);
    function getAuthorities() external view returns(Authorities memory);
}
