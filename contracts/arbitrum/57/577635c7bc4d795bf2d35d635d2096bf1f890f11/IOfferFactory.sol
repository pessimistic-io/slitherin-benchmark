// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IOfferFactory {

    /*************** EVENTS ***************/
    event CreatedOffer(address _entity, address _offer);
    event CurrentCreationCodeUpdated(address _entity, bytes _creationCode);
    event CurrentParamsUpdated(address _entity, bytes _params);
    
    struct OfferCreationConfig {
        bytes creationCode;
        bytes params;
        // Storage Gap
        bytes[40] __gap;
    }

    function createOffer(address _entity) external  returns (address _offer);

    function isDAOOffer(address _offer) external view returns(bool);

    function getOffersForEntity(address _entity) external view returns(address[] memory);

    function setCurrentCreationCodeForEntity(address _entity, bytes memory _creationCode) external;

    function setCurrentParamsForEntity(address _entity, bytes memory _params) external;

    function getCurrentCreationConfigForEntity(address _entity) external view returns(OfferCreationConfig memory);

    function getAllOffers() external view returns(address[] memory);
}
