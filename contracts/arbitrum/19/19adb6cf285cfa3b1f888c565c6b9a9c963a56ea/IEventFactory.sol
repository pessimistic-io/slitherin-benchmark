// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IEventFactory {

    /*************** EVENTS ***************/
    event CreatedEvent(address _entity, address _event);
    event CurrentCreationCodeUpdated(address _entity, bytes _creationCode);
    event CurrentParamsUpdated(address _entity, bytes _params);
    
    struct EventCreationConfig {
        bytes creationCode;
        bytes params;
    }

    function createEvent(address _entity) external  returns (address _event);

    function isDAOEvent(address _event) external view returns(bool);

    function getEventsForEntity(address _entity) external view returns(address[] memory);

    function setCurrentCreationCodeForEntity(address _entity, bytes memory _creationCode) external;

    function setCurrentParamsForEntity(address _entity, bytes memory _params) external;

    function getCurrentCreationConfigForEntity(address _entity) external view returns(EventCreationConfig memory);

    function getAllEvents() external view returns(address[] memory);
}
