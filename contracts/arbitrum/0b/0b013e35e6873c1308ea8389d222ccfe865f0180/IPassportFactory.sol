// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IPassportFactory {

    /*************** EVENTS ***************/
    event CreatedPassport(address _entity, address _passport);
    event CurrentCreationCodeUpdated(address _entity, bytes _creationCode);
    event CurrentParamsUpdated(address _entity, bytes _params);
    
    struct PassportCreationConfig {
        bytes creationCode;
        bytes params;
        // Storage Gap
        bytes[40] __gap;
    }

    function createPassport(address _entity) external  returns (address _passport);

    function isDAOPassport(address _passport) external view returns(bool);

    function getPassportsForEntity(address _entity) external view returns(address[] memory);

    function setCurrentCreationCodeForEntity(address _entity, bytes memory _creationCode) external;

    function setCurrentParamsForEntity(address _entity, bytes memory _params) external;

    function getCurrentCreationConfigForEntity(address _entity) external view returns(PassportCreationConfig memory);

    function getAllPassports() external view returns(address[] memory);
}
