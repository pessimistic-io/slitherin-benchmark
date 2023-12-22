// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./DAOAccessControlled.sol";
import "./Loot8UniformCollection.sol";
import "./ICollectionFactory.sol";
import "./Initializable.sol";

contract CollectionFactory is ICollectionFactory, Initializable, DAOAccessControlled {

    function initialize(address _authority) public initializer {
        DAOAccessControlled._setAuthority(_authority);
    }

    function createCollection(
        address _entity,
        string memory _name, 
        string memory _symbol,
        string memory _contractURI,
        bool _transferable,
        address _manager,
        address _helper,
        address _subscriptionManager,
        address _layerZeroEndpoint
    ) external returns (address) {

        if(block.chainid == 42161 || block.chainid == 421613) {
            require(
                IEntity(_entity).getEntityAdminDetails(_msgSender()).isActive,
                "UNAUTHORIZED"
            );
        } else {
            require(isTrustedForwarder(msg.sender), 'UNAUTHORIZED');
        }

        Loot8UniformCollection _loot8UniformCollection = 
                            new Loot8UniformCollection(
                                _name, 
                                _symbol,
                                _contractURI,
                                _transferable,
                                authority.getAuthorities().governor,
                                _helper,
                                authority.getAuthorities().forwarder,
                                _layerZeroEndpoint
                            );

        _loot8UniformCollection.setManager(_manager);
        _loot8UniformCollection.setSubscriptionManager(_subscriptionManager);
        _loot8UniformCollection.transferOwnership(_msgSender());

        emit CreatedCollection(_entity, address(_loot8UniformCollection));

        return address(_loot8UniformCollection);

    }
}
