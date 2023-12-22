// SPDX-License-Identifier: MIT
// Creator: base64.tech
pragma solidity ^0.8.13;

import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";

interface ISamuRiseItems {
    function getTotalNumberOfCollections() external view returns (uint256);
}

contract SamuRiseMetadataStateV2 is  UUPSUpgradeable, OwnableUpgradeable {
    mapping(uint256 => mapping(uint256 => bool)) public samuriseTokenIdToCollectionIdToEquipped;
    mapping(uint256 => mapping(uint256 => uint256)) public samuriseTokenIdToCollectionIdToConsumedBlockNumber;
    
    address public tokenContract;
    bool private initialized;

    event equipped(uint256 _samuriseTokenId, uint256 _collectionId);
    event unequipped(uint256 _samuriseTokenId, uint256 _collectionId);
    event consumed(uint256 _samuriseTokenId, uint256 _collectionId);

    /* v2 variables */
    mapping(uint256 => string) public collectionIdToCollectionType;
    mapping(string => uint256[]) public collectionTypeToArrayOfCollectionIds;

    function initialize(address _tokenContract) public initializer {
        require(!initialized, "Contract instance has already been initialized");
        initialized = true;
        tokenContract = _tokenContract;
        __UUPSUpgradeable_init();
        __Ownable_init();
    }

    function setCollectionIdToCollectionType(uint256 _collectionId, string memory _collectionType) external onlyOwner {
        collectionIdToCollectionType[_collectionId] = _collectionType;
        collectionTypeToArrayOfCollectionIds[_collectionType].push(_collectionId);
    }

    function equipSamuRise(uint256 _samuriseTokenId, uint256 _collectionId) public {
        require(msg.sender == tokenContract, "Function can only be called from token contract");

        string memory collectionType = collectionIdToCollectionType[_collectionId];
        uint256[] memory arrayOfCollectionIds = collectionTypeToArrayOfCollectionIds[collectionType];

        for(uint256 i = 0; i < arrayOfCollectionIds.length; i++) {
            uint256 collectionIdOfSameType = arrayOfCollectionIds[i];
            require(samuriseTokenIdToCollectionIdToEquipped[_samuriseTokenId][collectionIdOfSameType] == false, "token of same type is already equipped");
        }
       
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
        for(uint256 i = 0; i < ISamuRiseItems(tokenContract).getTotalNumberOfCollections(); i++) {
            if(isSamuRiseEquipped(_samuriseTokenId, i)) {
                arraySize++;
            }
        }
        uint256 arrayCounter = 0;
        uint256[] memory collectionIds = new uint256[](arraySize);
        for(uint256 i = 0; i < ISamuRiseItems(tokenContract).getTotalNumberOfCollections(); i++) {
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
