// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./DAOAccessControlled.sol";
import "./Loot8TieredCouponCollection.sol";
import "./ITieredCouponCollectionFactory.sol";
import "./Initializable.sol";

contract TieredCouponCollectionFactory is ITieredCouponCollectionFactory, Initializable, DAOAccessControlled {

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
        address _layerZeroEndpoint,
        address _tierCollection,
        uint256 _maxTokens
    ) external returns (address) {

        if(block.chainid == 42161 || block.chainid == 421613) {
            require(
                IEntity(_entity).getEntityAdminDetails(_msgSender()).isActive,
                "UNAUTHORIZED"
            );
        } else {
            require(isTrustedForwarder(msg.sender), 'UNAUTHORIZED');
        }

        Loot8TieredCouponCollection _loot8TieredCouponCollection = 
                            new Loot8TieredCouponCollection(
                                _name, 
                                _symbol,
                                _contractURI,
                                _transferable,
                                authority.getAuthorities().governor,
                                _helper,
                                authority.getAuthorities().forwarder,
                                _layerZeroEndpoint,
                                _tierCollection,
                                _maxTokens
                            );

        _loot8TieredCouponCollection.setManager(_manager);
        _loot8TieredCouponCollection.setSubscriptionManager(address(0));
        _loot8TieredCouponCollection.transferOwnership(_msgSender());

        emit CreatedCollection(_entity, address(_loot8TieredCouponCollection));

        return address(_loot8TieredCouponCollection);

    }
}
