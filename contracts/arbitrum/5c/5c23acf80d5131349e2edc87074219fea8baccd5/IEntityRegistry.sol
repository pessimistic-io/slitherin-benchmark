// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IEntityRegistry {

    /* ========== EVENTS ========== */
    event CreatedEntity(address _entity);

    enum FetchEntityTypes {
        DEPLOYED,
        ONBOARDED,
        ALL
    }

    function pushEntityAddress(address _entity) external;

    function removeEntityAddress(address _entity) external;

    function isDAOEntity(address _entity) external view returns(bool);

    function isOnboardedEntity(address _entity) external view returns(bool);

    function getAllEntities(bool _onlyActive) external view returns(address[] memory);

    function getAllEntitiesV2(bool _onlyActive, FetchEntityTypes _entityType) external view returns(address[] memory _entities);

    function setEntityFactory(address _newEntityFactory) external;

}
