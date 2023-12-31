// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./DAOAccessControlled.sol";
import "./ICollectionHelper.sol";
import "./ICollectionManager.sol";
import "./ITokenPriceCalculator.sol";
import "./ILoot8UniformCollection.sol";
import "./ERC165Checker.sol";
import "./Initializable.sol";

contract CollectionHelper is ICollectionHelper, Initializable, DAOAccessControlled {

    address collectionManager;

    uint16 LINKED;
    uint16 NOT_LINKED;
    uint16 NOT_EXIST;

    // Mapping Collection Address => List of linked collectibles
    // List of all collectibles linked to a given collectible
    // Eg: An offer linked to a passport, digital collectible linked
    // to a passport, offer linked to digital collectible linked to passport, etc.
    mapping(address => address[]) public linkedCollections;

    mapping(uint16 => string) private errorMessages;

    function initialize(
        address _collectionManager,
        address _authority
    ) public initializer {
        
        DAOAccessControlled._setAuthority(_authority);
        collectionManager = _collectionManager;

        LINKED = 1;
        NOT_LINKED = 2;
        NOT_EXIST = 3;

        errorMessages[LINKED] = "LINKED COLLECTIBLES";
        errorMessages[NOT_LINKED] = "NOT LINKED COLLECTIBLES";
        errorMessages[NOT_EXIST] = "COLLECTION DOES NOT EXIST";
    }

    /**
     * @notice Update contract URI for a given collection
     * @param _collection address Collection address for which URI needs to be updated
     * @param _contractURI string New contract URI for the collection
    */
    function updateContractURI(address _collection, string memory _contractURI) external 
    onlyEntityAdmin(ICollectionManager(collectionManager).getCollectionData(_collection).entity) {
        require(ICollectionManager(collectionManager).isCollection(_collection), "COLLECTION DOES NOT EXIST");
        uint256 collectionChainId = ICollectionManager(collectionManager).getCollectionChainId(_collection);
        require(collectionChainId == block.chainid, "COLLECTION ON FOREIGN CHAIN");
        require(ERC165Checker.supportsInterface(_collection, 0x96f8caa1), "COLLECTION NOT UNIFORM");
        string memory oldContractURI = ILoot8UniformCollection(_collection).contractURI();
        ILoot8UniformCollection(_collection).updateContractURI(_contractURI);
        emit ContractURIUpdated(_collection, oldContractURI, _contractURI);
    }

    function calculateRewards(address _collection, uint256 _quantity) public view returns(uint256) {
        require(ICollectionManager(collectionManager).isCollection(_collection), "COLLECTION DOES NOT EXIST");
        ITokenPriceCalculator tokenPriceCalculator = ITokenPriceCalculator(IDAOAuthority(authority).getAuthorities().tokenPriceCalculator);
        return tokenPriceCalculator.getTokensEligible(ICollectionManager(collectionManager).getCollectionData(_collection).price * _quantity);
    }

     /*
     * @notice Link two collections
     * @param _collection1 address
     * @param _collection2 address
    */
    function linkCollections(address _collection1, address _collection2) external {

        require(ICollectionManager(collectionManager).isCollection(_collection1) && ICollectionManager(collectionManager).isCollection(_collection2), errorMessages[NOT_EXIST]);

        require(
            IEntity(ICollectionManager(collectionManager).getCollectionData(_collection1).entity).getEntityAdminDetails(_msgSender()).isActive || 
            IEntity(ICollectionManager(collectionManager).getCollectionData(_collection2).entity).getEntityAdminDetails(_msgSender()).isActive,
            "UNAUTHORIZED"
        );

        require(!areLinkedCollections(_collection1, _collection2), errorMessages[LINKED]);
        
        linkedCollections[_collection1].push(_collection2);
        linkedCollections[_collection2].push(_collection1);

        // Emit an event marking a collectible holders friends visit to the club
        emit CollectionsLinked(_collection1, _collection1);
    }

    function delinkCollections(address _collection1, address _collection2) external {

        require(ICollectionManager(collectionManager).isCollection(_collection1) && ICollectionManager(collectionManager).isCollection(_collection2), errorMessages[NOT_EXIST]);

        require(
            IEntity(ICollectionManager(collectionManager).getCollectionData(_collection1).entity).getEntityAdminDetails(_msgSender()).isActive || 
            IEntity(ICollectionManager(collectionManager).getCollectionData(_collection2).entity).getEntityAdminDetails(_msgSender()).isActive,
            "UNAUTHORIZED"
        );

        require(areLinkedCollections(_collection1, _collection2), errorMessages[NOT_LINKED]);

        for (uint256 i = 0; i < linkedCollections[_collection1].length; i++) {
            if (linkedCollections[_collection1][i] == _collection2) {
                if(i < linkedCollections[_collection1].length - 1) {
                    linkedCollections[_collection1][i] = linkedCollections[_collection1][linkedCollections[_collection1].length-1];
                }
                linkedCollections[_collection1].pop();
                break;
            }
        }

        for (uint256 i = 0; i < linkedCollections[_collection2].length; i++) {
            if (linkedCollections[_collection2][i] == _collection1) {
                // delete linkedCollections[i];
                if(i < linkedCollections[_collection2].length - 1) {
                    linkedCollections[_collection2][i] = linkedCollections[_collection2][linkedCollections[_collection2].length-1];
                }
                linkedCollections[_collection2].pop();
                break;
            }
        }

        emit CollectionsDelinked(_collection1, _collection2);
    }

    function areLinkedCollections(address _collection1, address _collection2) public view returns(bool _areLinked) {
        require(ICollectionManager(collectionManager).isCollection(_collection1) && ICollectionManager(collectionManager).isCollection(_collection2), errorMessages[NOT_EXIST]);

        for (uint256 i = 0; i < linkedCollections[_collection1].length; i++) {
            if(linkedCollections[_collection1][i] == _collection2) {
                _areLinked = true;
                break;
            }
        }

    }

    function getAllLinkedCollections(address _collection) public view returns (address[] memory) {
        require(ICollectionManager(collectionManager).isCollection(_collection), errorMessages[NOT_EXIST]);
        return linkedCollections[_collection];
    }

}
