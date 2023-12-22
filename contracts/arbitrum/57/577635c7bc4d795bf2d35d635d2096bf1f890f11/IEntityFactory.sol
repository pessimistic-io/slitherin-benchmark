// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./ILocationBased.sol";

interface IEntityFactory is ILocationBased {

    /* ========== EVENTS ========== */
    event CreatedEntity(address _entity);

    function createEntity( 
        Area memory _area,
        string memory _dataURI,
        address _walletAddress
    ) external returns (address _entity);

    function isDAOEntity(address _entity) external view returns(bool);

    function getAllEntities() external view returns(address[] memory);

}
