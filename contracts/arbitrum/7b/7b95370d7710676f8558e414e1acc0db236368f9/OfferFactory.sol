// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./Offer.sol";
import "./DAOAccessControlled.sol";
import "./IOfferFactory.sol";
import "./Initializable.sol";

contract OfferFactory is IOfferFactory, Initializable, DAOAccessControlled {

    // List of all offers
    address[] public allOffers;

    // Offers for a given Entity
    // Entity address => Offers list
    mapping(address => address[]) public entityOffers;

    // Used to check for existence of a offer in the DAO eco-system
    mapping(address => bool) public offerExists;

    // Entity address => Offer Contract creation config
    // Entitywise current creation config for offers
    mapping(address => OfferCreationConfig) public currentCreationConfig;

    function initialize(address _authority) public initializer {
        DAOAccessControlled._setAuthority(_authority);
    }

    function createOffer(
        address _entity
    ) external onlyGovernor returns (address _offer) {

        bytes memory bytecode = abi.encodePacked(currentCreationConfig[_entity].creationCode, currentCreationConfig[_entity].params);

        assembly {
            _offer := create(0, add(bytecode, 32), mload(bytecode))
        }

        allOffers.push(_offer);

        offerExists[_offer] =  true;

        entityOffers[_entity].push(_offer);

        emit CreatedOffer(_entity, _offer);
    }

    function isDAOOffer(address _offer) public view returns(bool) {
        return offerExists[_offer];
    }

    function getOffersForEntity(address _entity) public view returns(address[] memory) {
        return entityOffers[_entity];
    }

    function setCurrentCreationCodeForEntity(address _entity, bytes memory _creationCode) public onlyEntityAdmin(_entity){
        currentCreationConfig[_entity].creationCode = _creationCode;
        emit CurrentCreationCodeUpdated(_entity, _creationCode);
    }

    function setCurrentParamsForEntity(address _entity, bytes memory _params) public onlyEntityAdmin(_entity){
        currentCreationConfig[_entity].params = _params;
        emit CurrentParamsUpdated(_entity, _params);
    }

    function getCurrentCreationConfigForEntity(address _entity) public view returns(OfferCreationConfig memory) {
        return currentCreationConfig[_entity];
    }

    function getAllOffers() public view returns(address[] memory) {
        return allOffers;
    }

    function pushOfferAddress(address _entity,address _offer) external onlyGovernor  {
        require(offerExists[_offer]==false,"Offer already exists");
        allOffers.push(_offer);
        offerExists[_offer] =  true;
        entityOffers[_entity].push(_offer);
        emit CreatedOffer(_entity, _offer);
    }

    function removeOfferAddress(address _entity,address _offer) external onlyGovernor  {
        require(offerExists[_offer] == true, "INVALID OFFER");
        require(ICollectible(_offer).getCollectibleData().entity == _entity, "ENTITY MISMATCH");
        
        for(uint256 i = 0; i < allOffers.length; i++) {
            if (allOffers[i] == _offer) {
                if(i < allOffers.length-1) {
                    allOffers[i] = allOffers[allOffers.length-1];
                }
                allOffers.pop();
                break;
            }
        }
        offerExists[_offer] = false;        
    }
}
