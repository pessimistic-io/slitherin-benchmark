/**************************************************************************************************************
// This contract consolidates all business logic for Collections and performs book-keeping
// and maintanence for collections and collectibles belonging to it
**************************************************************************************************************/

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./DAOAccessControlled.sol";

import "./IDispatcher.sol";
import "./ICollectionManager.sol";
import "./ICollectionHelper.sol";
import "./ILoot8Collection.sol";
import "./ITokenPriceCalculator.sol";
import "./ILoot8UniformCollection.sol";

import "./IERC721.sol";
import "./ERC165Checker.sol";
import "./Initializable.sol";
import "./IERC721Metadata.sol";

contract CollectionManager is ICollectionManager, Initializable, DAOAccessControlled {
    // Indicates if a collection is active in the Loot8 eco-system
    mapping(address => bool) public collectionIsActive;

    // List of collectible Ids minted for a collection
    mapping(address => uint256[]) public collectionCollectibleIds;

    // Mapping Collection Address => Collection Data
    // Maintains collection data holding information for
    // a given collection of collectibles at a given address
    mapping(address => CollectionData) public collectionData;

    // Mapping Collection Address => Collection Additional Data
    // Maintains collection additional data holding information for
    // a given collection of collectibles at a given address
    mapping(address => CollectionDataAdditional) public collectionDataAdditional;

    // Mapping Collection Address => Area
    // Area for which a given collection is valid
    mapping(address => Area) public area;

    // Mapping Collection Address => Collection Type
    // Type of Collection(Passport, Offer, Event, Digital Collection)
    mapping(address => CollectionType) public collectionType;

    // Mapping Collection Address => Collectible ID => Collectible Attributes
    // A mapping that maps collectible ids to its details for a given collection
    mapping(address => mapping(uint256 => CollectibleDetails)) public collectibleDetails;

    // Collections for a given Entity
    // Entity address => Collections list
    mapping(address => address[]) public entityCollections;

    // Used to check for existence of a collection in LOOT8 system
    // Excludes 3rd party collections
    mapping(address => bool) public collectionExists;

    address[] public allCollections;

    // Lists of all collections by types
    address[] public passports;
    address[] public events;
    address[] public offers;
    address[] public collections;

    uint16 INVALID;
    uint16 SUSPENDED;
    uint16 EXIST;
    uint16 NOT_EXIST;
    uint16 RETIRED;
    uint16 INACTIVE;

    mapping(uint16 => string) private errorMessages;

    mapping(address => uint256) public collectionChainId;

    function initialize(
        address _authority
    ) public initializer {
        DAOAccessControlled._setAuthority(_authority);

        INVALID = 1;
        SUSPENDED = 2;
        EXIST = 3;
        NOT_EXIST = 4;
        RETIRED = 5;
        INACTIVE = 6;
   
        errorMessages[INVALID] = "INVALID COLLECTIBLE";
        errorMessages[SUSPENDED] = "COLLECTIBLE SUSPENDED";
        errorMessages[EXIST] = "COLLECTION EXISTS";
        errorMessages[NOT_EXIST] = "COLLECTION DOES NOT EXIST";
        errorMessages[RETIRED] = "COLLECTION RETIRED";
        errorMessages[INACTIVE] = "COLLECTION INACTIVE";
    }

    function addCollection(
        address _collection,
        uint256 _chainId,
        CollectionType _collectionType,
        CollectionData calldata _collectionData,
        CollectionDataAdditional calldata _collectionDataAdditional,
        Area calldata _area
    ) external onlyEntityAdmin(_collectionData.entity) {

        require(_chainId != 0, "CHAIN ID CANNOT BE ZERO");

        if(_chainId == block.chainid) {
            require(
                ERC165Checker.supportsInterface(_collection, 0x80ac58cd) &&
                ERC165Checker.supportsInterface(_collection, 0x5b5e139f) &&
                ERC165Checker.supportsInterface(_collection, 0xfc45651b),
                "COLLECTION MISSING REQUIRED INTERFACES"
            );
        }

        require(_collectionType != CollectionType.ANY, errorMessages[INVALID]);
        require(!collectionExists[_collection], errorMessages[EXIST]);
    
        _addCollectionToLists(_collection, _collectionData.entity, _collectionType);

        // Set collection type
        collectionType[_collection] = _collectionType;

        // Set the data for the collection
        collectionData[_collection] = _collectionData;

        // Additional data for the collection
        collectionDataAdditional[_collection] = _collectionDataAdditional;

        // Set the area where collection is valid
        area[_collection] = _area;

        // Set collection as active
        collectionIsActive[_collection] = true;

        if (_collectionType ==  CollectionType.OFFER || _collectionType == CollectionType.EVENT) {
            IDispatcher dispatcher = IDispatcher(authority.getAuthorities().dispatcher);
            dispatcher.addOfferWithContext(_collection, _collectionData.maxPurchase, _collectionData.end);
        }

        collectionExists[_collection] = true;

        collectionChainId[_collection] = _chainId;

        emit CollectionAdded(_collection, _collectionType);
    }

    function removeCollection(address _collection) external onlyEntityAdmin(getCollectionData(_collection).entity) {      

        require(collectionExists[_collection], errorMessages[NOT_EXIST]);

        _removeCollectionFromLists(_collection, collectionData[_collection].entity, collectionType[_collection]);

        // Remove the data for the collection
        delete collectionData[_collection];

        // Remove the area where collection is valid
        delete area[_collection];

        // Remove collection as active
        delete collectionIsActive[_collection];

        // Remove chainId mapping
        delete collectionChainId[_collection];

        CollectionType _collectionType = collectionType[_collection];
        if (_collectionType ==  CollectionType.OFFER || _collectionType == CollectionType.EVENT) {
            IDispatcher dispatcher = IDispatcher(authority.getAuthorities().dispatcher);
            dispatcher.removeOfferWithContext(_collection);
        }

        collectionExists[_collection] = false;

        // Remove collection type
        delete collectionType[_collection];
    }

    function updateCollection(
        address _collection,
        CollectionData calldata _collectionData,
        CollectionDataAdditional calldata _collectionDataAdditional,
        Area calldata _area
    ) external onlyEntityAdmin(getCollectionData(_collection).entity) {

        require(collectionExists[_collection], errorMessages[NOT_EXIST]);

        collectionData[_collection] = _collectionData;
        collectionDataAdditional[_collection] = _collectionDataAdditional;
        area[_collection] = _area;

        emit CollectionDataUpdated(_collection);
    }

    function updateExistingCollectionChainIds() external onlyGovernor {
        for(uint256 i = 0; i < allCollections.length; i++) {
            if(collectionChainId[allCollections[i]] == 0) {
                collectionChainId[allCollections[i]] = block.chainid;
            }
        }
    }

    function _addCollectionToLists(address _collection, address _entity, CollectionType _collectionType) internal {
        allCollections.push(_collection);

        entityCollections[_entity].push(_collection);

        if(_collectionType == CollectionType.PASSPORT) {
            passports.push(_collection);
        } else if(_collectionType == CollectionType.OFFER) {
            offers.push(_collection);
        } else if(_collectionType == CollectionType.EVENT) {
            events.push(_collection);
        } else if(_collectionType == CollectionType.COLLECTION) {
            collections.push(_collection);
        }
    }

    function _removeCollectionFromLists(address _collection, address _entity, CollectionType _collectionType) internal {
        for (uint256 i = 0; i < allCollections.length; i++) {
            if (allCollections[i] == _collection) {
                if (i < allCollections.length) {
                    allCollections[i] = allCollections[allCollections.length - 1];
                }
                allCollections.pop();
            }
        }

        address[] storage _collections = entityCollections[_entity];

        for(uint256 i = 0; i < _collections.length; i++) {
            if(_collections[i] == _collection) {
                if(i < _collections.length) {
                    _collections[i] = _collections[_collections.length - 1];
                }
                _collections.pop();
            }
        }

        address[] storage list = passports;

        if(_collectionType == CollectionType.OFFER) {
            list = offers;
        } else if(_collectionType == CollectionType.EVENT) {
            list = events;
        } else if(_collectionType == CollectionType.COLLECTION) {
            list = collections;
        }

        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == _collection) {
                if (i < list.length) {
                    list[i] = list[list.length - 1];
                }
                list.pop();
            }
        }

    }

    function passedPreMintingChecks(address _patron, address _collection) public view returns(bool) {
        
        if(
            !collectionExists[_collection] || 
            !collectionIsActive[_collection] ||
            (collectionData[_collection].start > 0 && collectionData[_collection].end > 0 && 
            (collectionData[_collection].start > block.timestamp || collectionData[_collection].end <= block.timestamp))
        ) {
            return false;
        }
        
        if(collectionChainId[_collection] == block.chainid) {
            if(
                (collectionData[_collection].maxMint > 0 && collectionCollectibleIds[_collection].length >= collectionData[_collection].maxMint) ||
                ((collectionType[_collection] == CollectionType.PASSPORT || collectionType[_collection] == CollectionType.COLLECTION) && collectionDataAdditional[_collection].maxBalance == 0 && IERC721(_collection).balanceOf(_patron) >= 1) ||
                (collectionDataAdditional[_collection].maxBalance > 0 && IERC721(_collection).balanceOf(_patron) >= collectionDataAdditional[_collection].maxBalance) ||
                (collectionType[_collection] == CollectionType.COLLECTION && collectionData[_collection].passport != address(0) && IERC721(collectionData[_collection].passport).balanceOf(_patron) == 0)
            ) {
                return false;
            }
        }

        return true;

    }

    function mintCollectible(
        address _patron,
        address _collection
    ) external returns(uint256 _collectibleId) {

        require(
            _msgSender() == authority.getAuthorities().dispatcher ||
            (isTrustedForwarder(msg.sender) && 
            (collectionType[_collection] == CollectionType.PASSPORT || 
            collectionType[_collection] == CollectionType.COLLECTION)), 
            "UNAUTHORIZED"
        );

        // This function cannot mint tokens for collections on other chains
        if(collectionChainId[_collection] != block.chainid) {
            return 0;
        }

        if(!passedPreMintingChecks(_patron, _collection)) {
            return 0;
        }

        // require(collectionCollectibleIds[_collection].length < collectionData[_collection].maxMint, "OUT OF STOCK");

        // if(collectionType[_collection] == CollectionType.COLLECTION) {
        //     address _passport = collectionData[_collection].passport;
        //     uint256 _patronPassportId = getAllTokensForPatron(_passport, _patron)[0];
            
        //     require(collectibleDetails[_passport][_patronPassportId].visits >= collectionData[_collection].minVisits, "Not enough visits");
        //     require(collectibleDetails[_passport][_patronPassportId].rewardBalance >= collectionData[_collection].minRewardBalance, "Not enough reward balance");
        //     require(collectibleDetails[_passport][_patronPassportId].friendVisits >= collectionData[_collection].minFriendVisits, "Not enough friend visits");
        // }   

        _collectibleId = ILoot8Collection(_collection).getNextTokenId();
       
        ILoot8Collection(_collection).mint(_patron, _collectibleId);

        collectionCollectibleIds[_collection].push(_collectibleId);

        // Add details about the collectible to the collectibles object and add it to the mapping
        uint256[20] memory __gap;
        collectibleDetails[_collection][_collectibleId] = CollectibleDetails({
            id: _collectibleId,
            mintTime: block.timestamp, 
            isActive: true,
            rewardBalance: 0,
            visits: 0,
            friendVisits: 0,
            redeemed: false,
            __gap: __gap
        });

        emit CollectibleMinted(_collection, _collectibleId, collectionType[_collection]);  
    }

    /**
     * @notice Activation/Deactivation of a Collections Collectible token
     * @param _collection address Collection address to which the Collectible belongs
     * @param _collectibleId uint256 Collectible ID to be toggled
    */
    function toggle(address _collection, uint256 _collectibleId)
        external onlyBartender(collectionData[_collection].entity) {
        
        require(collectionExists[_collection], errorMessages[NOT_EXIST]);

        // Check if collection is active
        require(collectionIsActive[_collection], errorMessages[RETIRED]);

        CollectibleDetails storage _details = collectibleDetails[_collection][_collectibleId];

        // Check if Collectible with the given Id exists
        require(_details.id != 0, errorMessages[INVALID]);

        // Toggle the collectible
        _details.isActive = !_details.isActive;

        // Emit an event for Collectible toggling with status
        emit CollectibleToggled(_collection, _collectibleId, _details.isActive);
    }

    /**
     * @notice Transfers reward tokens to the patrons wallet when they purchase drinks/products.
     * @notice Internally also maintains and updates a tally around number of rewards held by a patron.
     * @notice Should be called when the bartender serves an order and receives payment for the drink.
     * @param _collection address Collection to which the patrons Collectible belongs
     * @param _patron address Patrons wallet address
     * @param _amount uint256 Amount of rewards to be credited
    */
    function creditRewards(
        address _collection,
        address _patron,
        uint256 _amount
    ) external onlyDispatcher {

        require(collectionExists[_collection], errorMessages[NOT_EXIST]);

        // Check if collectible is active
        require(collectionIsActive[_collection], errorMessages[RETIRED]);

        // Get the Collectible ID for the patron
        uint256 collectibleId = getAllTokensForPatron(_collection, _patron)[0];

        // Check if the patrons collectible is active
        require(collectibleDetails[_collection][collectibleId].isActive, errorMessages[SUSPENDED]);

        // Update a tally for reward balance in a collectible
        collectibleDetails[_collection][collectibleId].rewardBalance = 
                collectibleDetails[_collection][collectibleId].rewardBalance + int256(_amount);

        // Emit an event for reward credits to collectible with relevant details
        emit CreditRewards(_collection, collectibleId, _patron, _amount);
    }

    /**
     * @notice Burns reward tokens from patrons wallet when they redeem rewards for free drinks/products.
     * @notice Internally also maintains and updates a tally around number of rewards held by a patron.
     * @notice Should be called when the bartender serves an order in return for reward tokens as payment.
     * @param _collection address Collection to which the patrons Collectible belongs
     * @param _patron address Patrons wallet address
     * @param _amount uint256 Expiry timestamp for the Collectible
    */
    function debitRewards(
        address _collection,
        address _patron, 
        uint256 _amount
    ) external onlyDispatcher {

        require(collectionExists[_collection], errorMessages[NOT_EXIST]);

        // Check if collection is active
        require(collectionIsActive[_collection], errorMessages[RETIRED]);
        
        // Get the Collectible ID for the patron
        uint256 collectibleId = getAllTokensForPatron(_collection, _patron)[0];

        // Check if the patrons collectible is active
        require(collectibleDetails[_collection][collectibleId].isActive, errorMessages[SUSPENDED]);

        // Update a tally for reward balance in a collectible
        collectibleDetails[_collection][collectibleId].rewardBalance = 
                    collectibleDetails[_collection][collectibleId].rewardBalance - int256(_amount);
        
        // Emit an event for reward debits from a collectible with relevant details
        emit BurnRewards(_collection, collectibleId, _patron, _amount);
    }

    // /*
    //  * @notice Credits visits/friend visits to patrons passport
    //  * @notice Used as a metric to determine eligibility for special Collectible airdrops
    //  * @notice Should be called by the mobile app whenever the patron or his friend visits the club
    //  * @notice Only used for passport Collectible types
    //  * @param _collection address Collection to which the Collectible belongs
    //  * @param _collectibleId uint256 collectible id to which the visit needs to be added
    //  * @param _friend bool false=patron visit, true=friend visit
    // */
    // function addVisit(
    //     address _collection, 
    //     uint256 _collectibleId, 
    //     bool _friend
    // ) external onlyForwarder {

    //     // Check if collection is active
    //     require(collectionIsActive[_collection], errorMessages[RETIRED]);

    //     // Check if collectible with the given Id exists
    //     require(collectibleDetails[_collection][_collectibleId].id != 0, errorMessages[INVALID]);

    //     // Check if patron collectible is active or disabled
    //     require(collectibleDetails[_collection][_collectibleId].isActive, errorMessages[SUSPENDED]);

    //     // Credit visit to the collectible
    //     if(!_friend) {

    //         collectibleDetails[_collection][_collectibleId].visits = collectibleDetails[_collection][_collectibleId].visits + 1;
            
    //         // Emit an event marking a collectible holders visit to the club
    //         emit Visited(_collection, _collectibleId);

    //     } else {

    //         // Credit a friend visit to the collectible
    //         collectibleDetails[_collection][_collectibleId].friendVisits = collectibleDetails[_collection][_collectibleId].friendVisits + 1;

    //         // Emit an event marking a collectible holders friends visit to the club
    //         emit FriendVisited(_collection, _collectibleId);

    //     }

    // }

    /**
     * @notice Toggles mintWithLinked flag to true or false
     * @notice Can only be toggled by entity admin
     * @param _collection address
    */
    function toggleMintWithLinked(address _collection) external onlyEntityAdmin(collectionData[_collection].entity) {
        require(collectionExists[_collection], errorMessages[NOT_EXIST]);
        collectionData[_collection].mintWithLinked = !collectionData[_collection].mintWithLinked;
        emit  CollectionMintWithLinkedToggled(_collection, collectionData[_collection].mintWithLinked);
    }

    function retireCollection(address _collection) external onlyEntityAdmin(collectionData[_collection].entity) {
        require(collectionExists[_collection], errorMessages[NOT_EXIST]);
        require(collectionIsActive[_collection], errorMessages[RETIRED]);

        collectionIsActive[_collection] = false;
        emit CollectionRetired(_collection, collectionType[_collection]);
    }

    function setCollectibleRedemption(address _collection, uint256 _collectibleId) external onlyDispatcher {
        require(collectionExists[_collection], errorMessages[NOT_EXIST]);
        collectibleDetails[_collection][_collectibleId].redeemed = true;
    }

    function isCollection(address _collection) public view returns(bool) {
        return collectionExists[_collection];
    }

    function isRetired(address _collection, uint256 _collectibleId) external view returns(bool) {
        require(collectionExists[_collection], errorMessages[NOT_EXIST]);
        return !collectibleDetails[_collection][_collectibleId].isActive;
    }
    
    function checkCollectionActive(address _collection) public view returns(bool) {
        require(collectionExists[_collection], errorMessages[NOT_EXIST]);
        return collectionIsActive[_collection];
    }

    /*
     * @notice Returns collectible details for a given collectibleID belonging to a collection
     * @param _collection address The collection to which the collectible belongs
     * @param _collectibleId uint256 Collectible ID for which details need to be fetched
    */
    function getCollectibleDetails(address _collection, uint256 _collectibleId) external view returns(CollectibleDetails memory) {
        require(collectionExists[_collection], errorMessages[NOT_EXIST]);
        return collectibleDetails[_collection][_collectibleId];
    }

    function getCollectionType(address _collection) external view returns(CollectionType) {
        require(collectionExists[_collection], errorMessages[NOT_EXIST]);
        return collectionType[_collection];
    }

    function getCollectionData(address _collection) public view returns(CollectionData memory) {
        require(collectionExists[_collection], errorMessages[NOT_EXIST]);
        return collectionData[_collection];
    }

    function getLocationDetails(address _collection) external view returns(string[] memory, uint256) {
        require(collectionExists[_collection], errorMessages[NOT_EXIST]);
        return (area[_collection].points, area[_collection].radius);
    }

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
        CollectionType _collectionType) {
        require(collectionExists[_collection], errorMessages[NOT_EXIST]);
        _name = (collectionChainId[_collection] == block.chainid) ? IERC721Metadata(_collection).name() : '';
        _symbol = (collectionChainId[_collection] == block.chainid) ? IERC721Metadata(_collection).symbol() : '';
        _dataURI = (collectionChainId[_collection] == block.chainid) ? 
                    (ERC165Checker.supportsInterface(_collection, 0x96f8caa1) ? ILoot8UniformCollection(_collection).contractURI() : '') : '';
        _data = getCollectionData(_collection);
        _additionCollectionData = collectionDataAdditional[_collection];
        _areaPoints = area[_collection].points;
        _areaRadius = area[_collection].radius;
        _isActive = checkCollectionActive(_collection);
        _linkedCollections = ICollectionHelper(authority.collectionHelper()).getAllLinkedCollections(_collection);
        _collectionType = collectionType[_collection];
    }

    function _getListForCollectionType(CollectionType _collectionType) internal view returns(address[] memory) {
        
        if(_collectionType == CollectionType.PASSPORT) {
            return passports;
        } else if(_collectionType == CollectionType.OFFER) {
            return offers;
        } else if(_collectionType == CollectionType.EVENT) {
            return events;
        } else if(_collectionType == CollectionType.COLLECTION) {
            return collections;
        } else {
            return allCollections;
        }

    }

    function getCollectionsForEntity(address _entity, CollectionType _collectionType, bool _onlyActive) public view returns(address[] memory _entityCollections) {

        address[] memory _collections = entityCollections[_entity];

        uint256 count;
        for (uint256 i = 0; i < _collections.length; i++) {
            if (
                (_collectionType == CollectionType.ANY || collectionType[_collections[i]] == _collectionType) &&
                (!_onlyActive || checkCollectionActive(_collections[i]))
            ) {
                count++;
            }
        }
        
        _entityCollections = new address[](count);
        uint256 _idx;
        for(uint256 i = 0; i < _collections.length; i++) {
            if (
                (_collectionType == CollectionType.ANY || collectionType[_collections[i]] == _collectionType) &&
                (!_onlyActive || checkCollectionActive(_collections[i]))
            ) {
                _entityCollections[_idx] = _collections[i];
                _idx++;
            }
        }

    }

    function getAllCollectionsWithChainId(CollectionType _collectionType, bool _onlyActive) public view 
    returns(IExternalCollectionManager.ContractDetails[] memory _allCollections) {

        address[] memory collectionList = _getListForCollectionType(_collectionType);

        uint256 count;
        for (uint256 i = 0; i < collectionList.length; i++) {
            if (!_onlyActive || checkCollectionActive(collectionList[i])) {
                count++;
            }
        }
        
        _allCollections = new IExternalCollectionManager.ContractDetails[](count);
        uint256 _idx;
        for (uint256 i = 0; i < collectionList.length; i++) {
            if (!_onlyActive || checkCollectionActive(collectionList[i])) {
                _allCollections[_idx].source = collectionList[i];
                _allCollections[_idx].chainId = collectionChainId[collectionList[i]];
                _idx++;
            }
        }
    }

    function getAllCollectionsForPatron(CollectionType _collectionType, address _patron, bool _onlyActive) public view returns (address[] memory _allCollections) {
       
        address[] memory collectionList = _getListForCollectionType(_collectionType);
 
        uint256 count;
        for (uint256 i = 0; i < collectionList.length; i++) {
            if ( 
                (!_onlyActive || checkCollectionActive(collectionList[i])) &&
                collectionChainId[collectionList[i]] == block.chainid &&
                IERC721(collectionList[i]).balanceOf(_patron) > 0
            ) {
                count++;
            }
        }
            
        _allCollections = new address[](count);
        uint256 _idx;
        for (uint256 i = 0; i < collectionList.length; i++) {
            if( 
                (!_onlyActive || checkCollectionActive(collectionList[i])) &&
                (collectionChainId[collectionList[i]] == block.chainid) &&
                IERC721(collectionList[i]).balanceOf(_patron) > 0
            ) {
                _allCollections[_idx] = collectionList[i];
                _idx++;
            }
        }

    }

    function getCollectionChainId(address _collection) external view returns(uint256) {
        return collectionChainId[_collection];
    }

    function getAllTokensForPatron(address _collection, address _patron) public view returns(uint256[] memory _patronTokenIds) {
        require(isCollection(_collection), errorMessages[NOT_EXIST]);
        require(collectionChainId[_collection] == block.chainid, "COLLECTION ON FOREIGN CHAIN");
        IERC721 collection = IERC721(_collection);

        uint256 tokenId = 1;
        uint256 patronBalance = collection.balanceOf(_patron);
        uint256 i = 0;

        _patronTokenIds = new uint256[](patronBalance);

        while(i < patronBalance) {
            if(collection.ownerOf(tokenId) == _patron) {
                _patronTokenIds[i] = tokenId;
                i++;
            }

            tokenId++;

        }
    }

    // function getExternalCollectionsForPatron(address _patron) public view returns (address[] memory _collections) {
       
    //     address[] memory passportList = getAllCollectionsForPatron(CollectionType.PASSPORT, _patron, true);

    //     uint256 idx;
        
    //     for (uint256 i = 0; i < passportList.length; i++) {
    //         ContractDetails[] memory _wl = getWhitelistedCollectionsForPassport(passportList[i]);

    //         for (uint256 j = 0; j < _wl.length; j++) {
    //             if(IERC721(_wl[j].source).balanceOf(_patron) > 0) {
    //                 _collections[idx] = _wl[j].source;
    //                 idx++;
    //             }
    //         }
    //     }
    // }

}
