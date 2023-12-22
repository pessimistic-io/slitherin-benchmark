// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./IDAOAuthority.sol";
import "./ILocationBased.sol";
import "./IExternalCollectionManager.sol";
import "./ICollectionData.sol";


interface ICollectionManager is ICollectionData, ILocationBased {

    event CollectionAdded(address indexed _collection, CollectionType indexed _collectionType);

    event CollectionDataUpdated(address _collection);

    event CollectionRetired(address indexed _collection, CollectionType indexed _collectionType);

    event CollectibleMinted(address indexed _collection, uint256 indexed _collectibleId, CollectionType indexed _collectionType);

    event CollectibleToggled(address indexed _collection, uint256 indexed _collectibleId, bool _status);

    event CreditRewards(address indexed _collection, uint256 indexed _collectibleId, address indexed _patron, uint256 _amount);

    event BurnRewards(address indexed _collection, uint256 indexed _collectibleId, address indexed _patron, uint256 _amount);

    event Visited(address indexed _collection, uint256 indexed _collectibleId);

    event FriendVisited(address indexed _collection, uint256 indexed _collectibleId);

    event CollectionMintWithLinkedToggled(address indexed _collection, bool indexed _mintWithLinked);

    event CollectionWhitelisted(address indexed _passport, address indexed _source, uint256 indexed _chainId);

    event CollectionDelisted(address indexed _passport, address indexed _source, uint256 indexed _chainId);

    function addCollection(
        address _collection,
        uint256 _chainId,
        CollectionType _collectionType,
        CollectionData calldata _collectionData,
        CollectionDataAdditional calldata _collectionDataAdditional,
        Area calldata _area
    ) external;

    function updateCollection(
        address _collection,
        CollectionData calldata _collectionData,
        CollectionDataAdditional calldata _collectionDataAdditional,
        Area calldata _area
    ) external;

    function mintCollectible(
        address _patron,
        address _collection
    ) external returns(uint256 _collectibleId);

    function toggle(address _collection, uint256 _collectibleId) external;

    function creditRewards(
        address _collection,
        address _patron,
        uint256 _amount
    ) external;

    function debitRewards(
        address _collection,
        address _patron, 
        uint256 _amount
    ) external;

    // function addVisit(
    //     address _collection, 
    //     uint256 _collectibleId, 
    //     bool _friend
    // ) external;

    function toggleMintWithLinked(address _collection) external;

    //function whitelistCollection(address _source, uint256 _chainId, address _passport) external;

    //function getWhitelistedCollectionsForPassport(address _passport) external view returns(ContractDetails[] memory _wl);

    //function delistCollection(address _source, uint256 _chainId, address _passport) external;

    function setCollectibleRedemption(address _collection, uint256 _collectibleId) external;

    function isCollection(address _collection) external view returns(bool);
    
    function isRetired(address _collection, uint256 _collectibleId) external view returns(bool);

    function checkCollectionActive(address _collection) external view returns(bool);

    function getCollectibleDetails(address _collection, uint256 _collectibleId) external view returns(CollectibleDetails memory);

    function getCollectionType(address _collection) external view returns(CollectionType);

    function getCollectionData(address _collection) external view returns(CollectionData memory _collectionData);

    function getLocationDetails(address _collection) external view returns(string[] memory, uint256);

    function getCollectionsForEntity(address _entity, CollectionType _collectionType, bool _onlyActive) external view returns(address[] memory _entityCollections);

    function getAllCollections(CollectionType _collectionType, bool _onlyActive) external view returns(address[] memory _allCollections);

    function getAllCollectionsWithChainId(CollectionType _collectionType, bool _onlyActive) external view returns(IExternalCollectionManager.ContractDetails[] memory _allCollections);
    
    function getAllCollectionsForPatron(CollectionType _collectionType, address _patron, bool _onlyActive) external view returns(address[] memory _allCollections);

    function getCollectionChainId(address _collection) external view returns(uint256);

    function getCollectionInfo(address _collection) external view 
        returns (string memory _name,
        string memory _symbol,
        string memory _dataURI,
        CollectionData memory _data,
        CollectionDataAdditional memory _additionCollectionData,
        bool _isActive,
        string[] memory _areaPoints,
        uint256 _areaRadius,
        address[] memory _linkedCollections,
        CollectionType _collectionType);

    // function getExternalCollectionsForPatron(address _patron) external view returns (address[] memory _collections);

}
