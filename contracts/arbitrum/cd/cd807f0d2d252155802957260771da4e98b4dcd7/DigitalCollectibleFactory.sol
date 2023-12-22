// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./DigitalCollectible.sol";
import "./DAOAccessControlled.sol";
import "./IDigitalCollectibleFactory.sol";
import "./Initializable.sol";

contract DigitalCollectibleFactory is IDigitalCollectibleFactory, Initializable, DAOAccessControlled {

    // List of all digital collectibles
    address[] public allDigitalCollectibles;

    // Digital collectibles for a given Entity
    // Entity address => Digital Collectibles list
    mapping(address => address[]) public entityDigitalCollectibles;

    // Used to check for existence of a Digital Collectible in the DAO eco-system
    mapping(address => bool) public digitalCollectibleExists;

    // Entity address => DigitalCollectible Contract creation config
    // Entitywise current creation config for Digital Collectibles
    mapping(address => DigitalCollectibleCreationConfig) public currentCreationConfig;

    function initialize(address _authority) public initializer {
        DAOAccessControlled._setAuthority(_authority);
    }

    function createDigitalCollectible(
        address _entity
    ) external onlyGovernor returns (address _digitalCollectible) {

        bytes memory bytecode = abi.encodePacked(currentCreationConfig[_entity].creationCode, currentCreationConfig[_entity].params);

        assembly {
            _digitalCollectible := create(0, add(bytecode, 32), mload(bytecode))
        }

        allDigitalCollectibles.push(_digitalCollectible);

        digitalCollectibleExists[_digitalCollectible] =  true;

        entityDigitalCollectibles[_entity].push(_digitalCollectible);

        emit CreatedDigitalCollectible(_entity, _digitalCollectible);
    }

    function isDAODigitalCollectible(address _digitalCollectible) public view returns(bool) {
        return digitalCollectibleExists[_digitalCollectible];
    }

    function getDigitalCollectiblesForEntity(address _entity) public view returns(address[] memory) {
        return entityDigitalCollectibles[_entity];
    }

    function setCurrentCreationCodeForEntity(address _entity, bytes memory _creationCode) public onlyEntityAdmin(_entity){
        currentCreationConfig[_entity].creationCode = _creationCode;
        emit CurrentCreationCodeUpdated(_entity, _creationCode);
    }

    function setCurrentParamsForEntity(address _entity, bytes memory _params) public onlyEntityAdmin(_entity){
        currentCreationConfig[_entity].params = _params;
        emit CurrentParamsUpdated(_entity, _params);
    }

    function getCurrentCreationConfigForEntity(address _entity) public view returns(DigitalCollectibleCreationConfig memory) {
        return currentCreationConfig[_entity];
    }

    function getAllDigitalCollectibles() public view returns(address[] memory) {
        return allDigitalCollectibles;
    }

    function pushDigitalCollectibleAddress(address _entity,address _digitalCollectible) external onlyGovernor  {
        require(digitalCollectibleExists[_digitalCollectible]==false,"Digital Collectible already exists");
        allDigitalCollectibles.push(_digitalCollectible);
        digitalCollectibleExists[_digitalCollectible] =  true;
        entityDigitalCollectibles[_entity].push(_digitalCollectible);
        emit CreatedDigitalCollectible(_entity, _digitalCollectible);
    }

    function removeDigitalCollectibleAddress(address _entity,address _digitalCollectible) external onlyGovernor  {
        require(digitalCollectibleExists[_digitalCollectible] == true, "INVALID DIGITAL COLLECTIBLE");
        require(ICollectible(_digitalCollectible).getCollectibleData().entity == _entity, "ENTITY MISMATCH");
        
        for(uint256 i = 0; i < allDigitalCollectibles.length; i++) {
            if (allDigitalCollectibles[i] == _digitalCollectible) {
                if(i < allDigitalCollectibles.length-1) {
                    allDigitalCollectibles[i] = allDigitalCollectibles[allDigitalCollectibles.length-1];
                }
                allDigitalCollectibles.pop();
                break;
            }
        }
        digitalCollectibleExists[_digitalCollectible] = false;        
    }
}
