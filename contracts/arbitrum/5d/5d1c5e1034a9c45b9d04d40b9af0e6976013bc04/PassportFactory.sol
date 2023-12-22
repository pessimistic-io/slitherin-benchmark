// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./Passport.sol";
import "./DAOAccessControlled.sol";
import "./ICollectible.sol";
import "./IPassportFactory.sol";
import "./Initializable.sol";

contract PassportFactory is IPassportFactory, Initializable, DAOAccessControlled {

    // List of all passports
    address[] public allPassports;

    // Passports for a given Entity
    // Entity address => Passports list
    mapping(address => address[]) public entityPassports;

    // Used to check for existence of a passport in the DAO eco-system
    mapping(address => bool) public passportExists;

    // Entity address => Passports Contract creation config
    // Entitywise current creation config for passports
    mapping(address => PassportCreationConfig) public currentCreationConfig;

    function initialize(address _authority) public initializer {
        DAOAccessControlled._setAuthority(_authority);
    }

    function createPassport(
        address _entity
    ) external onlyGovernor returns (address _passport) {

        bytes memory bytecode = abi.encodePacked(currentCreationConfig[_entity].creationCode, currentCreationConfig[_entity].params);

        assembly {
            _passport := create(0, add(bytecode, 32), mload(bytecode))
        }

        allPassports.push(_passport);

        passportExists[_passport] =  true;

        entityPassports[_entity].push(_passport);

        emit CreatedPassport(_entity, _passport);
    }

    function isDAOPassport(address _passport) public view returns(bool) {
        return passportExists[_passport];
    }

    function getPassportsForEntity(address _entity) public view returns(address[] memory) {
        return entityPassports[_entity];
    }

    function setCurrentCreationCodeForEntity(address _entity, bytes memory _creationCode) public onlyEntityAdmin(_entity){
        currentCreationConfig[_entity].creationCode = _creationCode;
        emit CurrentCreationCodeUpdated(_entity, _creationCode);
    }

    function setCurrentParamsForEntity(address _entity, bytes memory _params) public onlyEntityAdmin(_entity){
        currentCreationConfig[_entity].params = _params;
        emit CurrentParamsUpdated(_entity, _params);
    }

    function getCurrentCreationConfigForEntity(address _entity) public view returns(PassportCreationConfig memory) {
        return currentCreationConfig[_entity];
    }

    function getAllPassports() public view returns(address[] memory) {
        return allPassports;
    }

    function pushPassportAddress(address _entity,address _passport) external onlyGovernor  {
        require(passportExists[_passport]==false,"Passport already exists");
        allPassports.push(_passport);
        passportExists[_passport] =  true;
        entityPassports[_entity].push(_passport);
        emit CreatedPassport(_entity, _passport);
    }    
}
