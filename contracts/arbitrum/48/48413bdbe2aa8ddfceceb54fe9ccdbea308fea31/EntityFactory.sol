// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./Entity.sol";
import "./DAOAccessControlled.sol";
import "./IEntityFactory.sol";
import "./Initializable.sol";
contract EntityFactory is IEntityFactory, Initializable, DAOAccessControlled {

    // List of all entities
    address[] public allEntities;

    // Used to check for existence of an entity in the DAO eco-system
    mapping(address => bool) public entityExists;

    function initialize(address _authority) public initializer {
        DAOAccessControlled._setAuthority(_authority);
    }

    function createEntity( 
        Area memory _area,
        string memory _dataURI,
        address _walletAddress
    ) external onlyGovernor returns (address _entity) {

        bytes memory bytecode = abi.encodePacked(
                                    type(Entity).creationCode, 
                                    abi.encode(
                                        _area,
                                        _dataURI,
                                        _walletAddress
                                    )
                                );

        bytes32 salt = keccak256(abi.encodePacked(_walletAddress));

        assembly {
            _entity := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        allEntities.push(_entity);

        entityExists[_entity] =  true;

        emit CreatedEntity(_entity);
    }

    function isDAOEntity(address _entity) public view returns(bool) {
        return entityExists[_entity];
    }

    function getAllEntities() public view returns(address[] memory) {
        return allEntities;
    }

    function pushEntityAddress(address _entity) external onlyGovernor  {
        require(entityExists[_entity]==false,"Entity already exists");
        allEntities.push(_entity);
        entityExists[_entity] =  true;
        emit CreatedEntity(_entity);
    }

    function removeEntityAddress(address _entity) external onlyGovernor  {
        require(entityExists[_entity] == true, "INVALID ENTITY");

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
    } 
}
