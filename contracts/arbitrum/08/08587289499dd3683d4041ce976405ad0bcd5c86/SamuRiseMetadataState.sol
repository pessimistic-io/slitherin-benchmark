// SPDX-License-Identifier: MIT
// Creator: base64.tech
pragma solidity ^0.8.13;

import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";

interface ISamuRiseEquipment {
    function getTotalNumberOfCollections() external view returns (uint256);
}

contract SamuRiseMetadataStateTEST is  UUPSUpgradeable, OwnableUpgradeable {
    mapping(uint256 => mapping(uint256 => bool)) public samuriseTokenIdToCollectionIdToEquipped;
    mapping(uint256 => mapping(uint256 => uint256)) public samuriseTokenIdToCollectionIdToConsumedBlockNumber;
    
    address public tokenContract;
    bool private initialized;

    event equipped(uint256 _samuriseTokenId, uint256 _collectionId);
    event unequipped(uint256 _samuriseTokenId, uint256 _collectionId);
    event consumed(uint256 _samuriseTokenId, uint256 _collectionId);

    function initialize(address _tokenContract) public initializer {
        require(!initialized, "Contract instance has already been initialized");
        initialized = true;
        tokenContract = _tokenContract;
        __UUPSUpgradeable_init();
        __Ownable_init();
    }

    function equipSamuRise(uint256 _samuriseTokenId, uint256 _collectionId) public {
        require(msg.sender == tokenContract, "Function can only be called from token contract");
       
        samuriseTokenIdToCollectionIdToEquipped[_samuriseTokenId][_collectionId] = true;        
        emit equipped(_samuriseTokenId, _collectionId);
    }

    function unequipSamuRise(uint256 _samuriseTokenId, uint256 _collectionId) public {
        require(msg.sender == tokenContract, "Function can only be called from token contract");
       
        samuriseTokenIdToCollectionIdToEquipped[_samuriseTokenId][_collectionId] = false;        
        emit unequipped(_samuriseTokenId, _collectionId);
    }

    function consume(uint256 _samuriseTokenId, uint256 _collectionId) public {
        require(msg.sender == tokenContract, "Function can only be called from token contract");

        samuriseTokenIdToCollectionIdToConsumedBlockNumber[_samuriseTokenId][_collectionId] = block.number;        
        emit consumed(_samuriseTokenId, _collectionId);
    }

    function isSamuRiseEquipped(uint256 _samuriseTokenId, uint256 _collectionId) public view returns (bool) {
        return samuriseTokenIdToCollectionIdToEquipped[_samuriseTokenId][_collectionId];
    }

    function getSamuriseConsumedBlockBlockNumber(uint256 _samuriseTokenId, uint256 _collectionId) public view returns (uint256) {
        return samuriseTokenIdToCollectionIdToConsumedBlockNumber[_samuriseTokenId][_collectionId];
    }

    function getSamuRiseCollectionsEquipped(uint256 _samuriseTokenId) external view returns (uint256[] memory) {
        uint256 arraySize = 0;
        for(uint256 i = 0; i < ISamuRiseEquipment(tokenContract).getTotalNumberOfCollections(); i++) {
            if(isSamuRiseEquipped(_samuriseTokenId, i)) {
                arraySize++;
            }
        }
        uint256 arrayCounter = 0;
        uint256[] memory collectionIds = new uint256[](arraySize);
        for(uint256 i = 0; i < ISamuRiseEquipment(tokenContract).getTotalNumberOfCollections(); i++) {
            if(isSamuRiseEquipped(_samuriseTokenId, i)) {
                collectionIds[arrayCounter] = i;
                arrayCounter++;
            }
        }

        return collectionIds;
    }

    /* owner functions */
   function _authorizeUpgrade(address) internal override onlyOwner {}

}
