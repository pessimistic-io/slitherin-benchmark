// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./Offer.sol";
import "./DAOAccessControlled.sol";
import "./IEventFactory.sol";
import "./Initializable.sol";

contract EventFactory is IEventFactory, Initializable, DAOAccessControlled {

    // List of all events
    address[] public allEvents;

    // Events for a given Entity
    // Entity address => Events list
    mapping(address => address[]) public entityEvents;

    // Used to check for existence of an event in the DAO eco-system
    mapping(address => bool) public eventExists;

    // Entity address => Event Contract creation config
    // Entitywise current creation config for events
    mapping(address => EventCreationConfig) public currentCreationConfig;

    function initialize(address _authority) public initializer {
        DAOAccessControlled._setAuthority(_authority);
    }

    function createEvent(
        address _entity
    ) external onlyGovernor returns (address _event) {

        bytes memory bytecode = abi.encodePacked(currentCreationConfig[_entity].creationCode, currentCreationConfig[_entity].params);

        assembly {
            _event := create(0, add(bytecode, 32), mload(bytecode))
        }

        allEvents.push(_event);

        eventExists[_event] =  true;

        entityEvents[_entity].push(_event);

        emit CreatedEvent(_entity, _event);
    }

    function isDAOEvent(address _event) public view returns(bool) {
        return eventExists[_event];
    }

    function getEventsForEntity(address _entity) public view returns(address[] memory) {
        return entityEvents[_entity];
    }

    function setCurrentCreationCodeForEntity(address _entity, bytes memory _creationCode) public onlyEntityAdmin(_entity){
        currentCreationConfig[_entity].creationCode = _creationCode;
        emit CurrentCreationCodeUpdated(_entity, _creationCode);
    }

    function setCurrentParamsForEntity(address _entity, bytes memory _params) public onlyEntityAdmin(_entity){
        currentCreationConfig[_entity].params = _params;
        emit CurrentParamsUpdated(_entity, _params);
    }

    function getCurrentCreationConfigForEntity(address _entity) public view returns(EventCreationConfig memory) {
        return currentCreationConfig[_entity];
    }

    function getAllEvents() public view returns(address[] memory) {
        return allEvents;
    }

    function pushEventAddress(address _entity,address _event) external onlyGovernor  {
        require(eventExists[_event]==false,"Event already exists");
        allEvents.push(_event);
        eventExists[_event] =  true;
        entityEvents[_entity].push(_event);
        emit CreatedEvent(_entity, _event);
    }

    function removeEventAddress(address _entity,address _event) external onlyGovernor  {
        require(eventExists[_event] == true, "INVALID EVENT");
        require(ICollectible(_event).getCollectibleData().entity == _entity, "ENTITY MISMATCH");
        
        for(uint256 i = 0; i < allEvents.length; i++) {
            if (allEvents[i] == _event) {
                if(i < allEvents.length-1) {
                    allEvents[i] = allEvents[allEvents.length-1];
                }
                allEvents.pop();
                break;
            }
        }
        eventExists[_event] = false;        
    }
}
