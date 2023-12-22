// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./DAOAccessControlled.sol";
import "./ICollectionManager.sol";
import "./IExternalCollectionManager.sol";
import "./Initializable.sol";

contract ExternalCollectionManager is IExternalCollectionManager, Initializable, DAOAccessControlled {

    // (address => chainId => index) 1-based index lookup for third-party collections whitelisting/delisting
    // Mapping Passport => Collection address => Chain Id => Index in whitelistedCollections[passport]
    mapping(address => mapping(address => mapping(uint256 => uint256))) public whitelistedCollectionsLookup;
    
    // List of whitelisted third-party collection contracts
    // Mapping Passport to List of linked external collections
    mapping(address => ContractDetails[]) public whitelistedCollections;

    uint16 NOT_PASSPORT;
    uint16 EXIST;
    uint16 NOT_EXIST;
    mapping(uint16 => string) private errorMessages;

    function initialize(
        address _authority
    ) public initializer {
        
        DAOAccessControlled._setAuthority(_authority);

        NOT_PASSPORT = 1;
        EXIST = 2;
        NOT_EXIST = 3;
        errorMessages[NOT_PASSPORT] = "NOT A PASSPORT";
        errorMessages[EXIST] = "COLLECTION EXISTS";
        errorMessages[NOT_EXIST] = "COLLECTION DOES NOT EXIST";
    }


    /**
     * @notice            add an address to third-party collections whitelist
     * @param _source     address collection contract address
     * @param _chainId    uint256 chainId where contract is deployed
     * @param _passport   address Passport for which the the collection be whitelisted
     * @notice _passport = address(0) means that the collectible is not linked to any passport
     */
    function whitelistCollection(address _source, uint256 _chainId, address _passport) external {
        
        if(_passport != address(0)) {

            require(
                ICollectionManager(authority.getAuthorities().collectionManager).getCollectionType(_passport) == CollectionType.PASSPORT,
                errorMessages[NOT_PASSPORT]
            );

            require(whitelistedCollectionsLookup[address(0)][_source][_chainId] == 0, "COLLECTION IS UNLINKED TYPE AND CANNOT BE LINKED TO A PASSPORT");

            require(
                IEntity(
                    ICollectionManager(authority.getAuthorities().collectionManager).getCollectionData(_passport).entity
                ).getEntityAdminDetails(_msgSender()).isActive,
                "UNAUTHORIZED"
            );

        } else {
            require(_msgSender() == authority.getAuthorities().governor, "UNAUTHORIZED");
        }
        
        uint256 index = whitelistedCollectionsLookup[_passport][_source][_chainId];
        require(index == 0, errorMessages[EXIST]);

        uint256[5] memory __gap;
        whitelistedCollections[_passport].push(ContractDetails({
            source: _source,
            chainId: _chainId,
            __gap: __gap
        }));

        whitelistedCollectionsLookup[_passport][_source][_chainId] = whitelistedCollections[_passport].length; // store as 1-based index
        emit CollectionWhitelisted(_passport, _source, _chainId);
    }

    function getWhitelistedCollectionsForPassport(address _passport) public view returns(ContractDetails[] memory _wl) {
        _wl = new ContractDetails[](whitelistedCollections[_passport].length);
        for(uint256 i = 0; i < whitelistedCollections[_passport].length; i++) {
            _wl[i] = whitelistedCollections[_passport][i];
        }
    }

    /**
     * @notice          remove an address from third-party collections whitelist
     * @param _source   collections contract address
     * @param _chainId  chainId where contract is deployed
     * @param _passport address Passport for which the the collection be whitelisted
     */
    function delistCollection(address _source, uint256 _chainId, address _passport) external {

        if(_passport != address(0)) {

            require(
                ICollectionManager(authority.getAuthorities().collectionManager).getCollectionType(_passport) == CollectionType.PASSPORT,
                errorMessages[NOT_PASSPORT]
            );

            require(
                IEntity(
                    ICollectionManager(authority.getAuthorities().collectionManager).getCollectionData(_passport).entity
                ).getEntityAdminDetails(_msgSender()).isActive,
                "UNAUTHORIZED"
            );

        } else {
            require(_msgSender() == authority.getAuthorities().governor, "UNAUTHORIZED");
        }
        
        uint256 index = whitelistedCollectionsLookup[_passport][_source][_chainId];
        require(index > 0, errorMessages[NOT_EXIST]);
        index -= 1; // convert to 0-based index

        if (index < whitelistedCollections[_passport].length - 1) {
            whitelistedCollections[_passport][index] = whitelistedCollections[_passport][whitelistedCollections[_passport].length - 1];
        }
        whitelistedCollections[_passport].pop();
        delete whitelistedCollectionsLookup[_passport][_source][_chainId];

        emit CollectionDelisted(_passport, _source, _chainId);
    }

}

