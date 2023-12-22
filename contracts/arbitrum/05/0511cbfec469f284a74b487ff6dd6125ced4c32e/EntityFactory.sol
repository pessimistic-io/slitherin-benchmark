// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./Entity.sol";
import "./DAOAccessControlled.sol";
import "./IEntityFactory.sol";
import "./IEntityRegistry.sol";

import "./BeaconProxy.sol";
import "./UpgradeableBeacon.sol";

contract EntityFactory is IEntityFactory, DAOAccessControlled {

    address public onboarder;
    address public entityRegistry;
    address immutable public entityBeacon;    

    constructor(
        address _authority, 
        address _entityRegistry
    ) {
        DAOAccessControlled._setAuthority(_authority);
        entityRegistry = _entityRegistry;
        
        UpgradeableBeacon _entityBeacon = new UpgradeableBeacon(address(new Entity()));
        _entityBeacon.transferOwnership(authority.getAuthorities().governor);
        
        entityBeacon = address(_entityBeacon);
    }

    function setOnboarder(address _newOnboarder) external onlyGovernor {
        address oldOnboarder = onboarder;
        onboarder = _newOnboarder;
        emit OnboarderSet(oldOnboarder, onboarder);
    }

    function createEntity(bytes memory _creationData) external returns(address _entity) {
        
        require(onboarder != address(0), "ONBOARDER NOT SET");

        require(
            _msgSender() == authority.getAuthorities().governor ||
            _msgSender() == onboarder,
            "UNAUTHORIZED"
        );

        BeaconProxy entityAddress = new BeaconProxy(
            entityBeacon,
            _creationData
        );

        _entity = address(entityAddress);
        IEntityRegistry(entityRegistry).pushEntityAddress(_entity);
        emit EntityCreated(_entity);
        
    }

}
