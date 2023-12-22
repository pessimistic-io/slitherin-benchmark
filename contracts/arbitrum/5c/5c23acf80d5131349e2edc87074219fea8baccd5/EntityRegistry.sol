// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./Entity.sol";
import "./DAOAccessControlled.sol";
import "./IEntityRegistry.sol";
import "./Initializable.sol";

contract EntityRegistry is IEntityRegistry, Initializable, DAOAccessControlled {

    // List of all entities
    address[] public allEntities;

    // Used to check for existence of an entity in the DAO eco-system
    mapping(address => bool) public entityExists;

    // Flag to determine if an entity was onboarded or deployed by governor
    mapping(address => bool) public entityOnboarded;

    address public onboarder;

    event EntityFactoryUpdated(address oldEntityFactory, address entityFactory);

    address public entityFactory;

    function initialize(address _authority) public initializer {
        DAOAccessControlled._setAuthority(_authority);
    }

    function initializer2(address _entityFactory) public reinitializer(2) {
        entityFactory = _entityFactory;
    }

    function pushEntityAddress(address _entity) external {
        
        require(
            _msgSender() == authority.getAuthorities().governor ||
            _msgSender() == entityFactory,
            "UNAUTHORIZED"
        );

        require(!entityExists[_entity], "Entity already exists");
        allEntities.push(_entity);
        entityExists[_entity] = true;
        
        if(_msgSender() == entityFactory) {
            entityOnboarded[_entity] = true;
        }

        emit CreatedEntity(_entity);
    }

    function removeEntityAddress(address _entity) external onlyGovernor  {
        require(entityExists[_entity], "INVALID ENTITY");

        for(uint256 i = 0; i < allEntities.length; i++) {
            if (allEntities[i] == _entity) {
                if(i < allEntities.length-1) {
                    allEntities[i] = allEntities[allEntities.length-1];
                }
                allEntities.pop();
                break;
            }
        }

        entityExists[_entity] = false;
        delete entityOnboarded[_entity];
    }

    function isDAOEntity(address _entity) public view returns(bool) {
        return entityExists[_entity];
    }

    function isOnboardedEntity(address _entity) public view returns(bool) {
        return entityOnboarded[_entity];
    }

    function getAllEntities(bool _onlyActive) public view returns(address[] memory _entities) {

        address[] memory _ents = allEntities;

        uint256 count;
        for (uint256 i = 0; i < _ents.length; i++) {
            if(!_onlyActive || IEntity(_ents[i]).getEntityData().isActive) {
                count++;
            }
        }
        
        _entities = new address[](count);
        uint256 _idx;
        for(uint256 i = 0; i < _ents.length; i++) {
            if (!_onlyActive || IEntity(_ents[i]).getEntityData().isActive) {
                _entities[_idx] = _ents[i];
                _idx++;
            }
        }
    }

    function getAllEntitiesV2(bool _onlyActive, FetchEntityTypes _entityType) public view returns(address[] memory _entities) {

        address[] memory _ents = allEntities;

        uint256 count;
        for (uint256 i = 0; i < _ents.length; i++) {
            if (
                (!_onlyActive || IEntity(_ents[i]).getEntityData().isActive) &&
                (
                    _entityType == FetchEntityTypes.ALL || 
                    (_entityType == FetchEntityTypes.DEPLOYED && !entityOnboarded[_ents[i]]) ||
                    (_entityType == FetchEntityTypes.ONBOARDED && entityOnboarded[_ents[i]])
                )
            ) {
                count++;
            }
        }
        
        _entities = new address[](count);
        uint256 _idx;
        for(uint256 i = 0; i < _ents.length; i++) {
            if (
                (!_onlyActive || IEntity(_ents[i]).getEntityData().isActive) &&
                (
                    _entityType == FetchEntityTypes.ALL || 
                    (_entityType == FetchEntityTypes.DEPLOYED && !entityOnboarded[_ents[i]]) ||
                    (_entityType == FetchEntityTypes.ONBOARDED && entityOnboarded[_ents[i]])
                )
            ) {
                _entities[_idx] = _ents[i];
                _idx++;
            }
        }
    }

    function setEntityFactory(address _newEntityFactory) public onlyGovernor {
        address oldEntityFactory = entityFactory;
        entityFactory = _newEntityFactory;
        emit EntityFactoryUpdated(oldEntityFactory, entityFactory);
    }
}
