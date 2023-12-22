// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./DAOAccessControlled.sol";
import "./Loot8POAPCollection.sol";
import "./IPOAPCollectionFactory.sol";
import "./Initializable.sol";

contract POAPCollectionFactory is IPOAPCollectionFactory, Initializable, DAOAccessControlled {

    function initialize(address _authority) public initializer {
        DAOAccessControlled._setAuthority(_authority);
    }

    function createCollection(
        address _entity,
        string memory _name, 
        string memory _symbol,
        string memory _contractURI,
        bool _transferable,
        address _layerZeroEndpoint,
        uint256 _autoTokenIdStart
    ) external returns (address) {

        if(block.chainid == 42161 || block.chainid == 421613) {
            require(
                IEntity(_entity).getEntityAdminDetails(_msgSender()).isActive,
                "UNAUTHORIZED"
            );
        } else {
            require(isTrustedForwarder(msg.sender), 'UNAUTHORIZED');
        }

        Loot8POAPCollection _loot8POAPCollection = 
                            new Loot8POAPCollection(
                                _name, 
                                _symbol,
                                _contractURI,
                                _transferable,
                                authority.getAuthorities().governor,
                                authority.getAuthorities().forwarder,
                                _layerZeroEndpoint,
                                _autoTokenIdStart
                            );

       _loot8POAPCollection.transferOwnership(_msgSender());

        emit CreatedCollection(_entity, address(_loot8POAPCollection));

        return address(_loot8POAPCollection);

    }
}
