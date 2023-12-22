// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface ITieredCouponCollectionFactory {

    /*************** EVENTS ***************/
    event CreatedCollection(address _entity, address _collection);

    function createCollection(
        address _entity,
        string memory _name, 
        string memory _symbol,
        string memory _contractURI,
        bool _transferable,
        address _helper,
        address _layerZeroEndpoint,
        address _tierCollection,
        uint256 _maxTokens
    ) external returns (address);
    
}
