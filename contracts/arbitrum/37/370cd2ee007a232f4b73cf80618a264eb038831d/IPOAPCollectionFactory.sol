// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IPOAPCollectionFactory {

    /*************** EVENTS ***************/
    event CreatedCollection(address _entity, address _collection);

    function createCollection(
        address _entity,
        string memory _name, 
        string memory _symbol,
        string memory _contractURI,
        bool _transferable,
        address _layerZeroEndpoint,
        uint256 _autoTokenIdStart
    ) external returns (address);
    
}
