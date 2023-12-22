pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import "./DIDRegistryLibrary.sol";
import "./ProvenanceRegistry.sol";
import "./OwnableUpgradeable.sol";

/**
 * @title DID Factory
 * @author Nevermined
 *
 * @dev Implementation of the DID Registry.
 */
abstract contract DIDFactory is ProvenanceRegistry { 
    
    /**
     * @dev The DIDRegistry Library takes care of the basic DID storage functions.
     */
    using DIDRegistryLibrary for DIDRegistryLibrary.DIDRegisterList;

    /**
     * @dev state storage for the DID registry
     */
    DIDRegistryLibrary.DIDRegisterList internal didRegisterList;

    // DID -> Address -> Boolean Permission
    mapping(bytes32 => mapping(address => bool)) internal didPermissions;
    
    address public manager;

    //////////////////////////////////////////////////////////////
    ////////  MODIFIERS   ////////////////////////////////////////
    //////////////////////////////////////////////////////////////

    
    modifier onlyDIDOwner(bytes32 _did)
    {
        require(
            isDIDOwner(_msgSender(), _did),
            'Only owner'
        );
        _;
    }

    modifier onlyOwnerProviderOrDelegated(bytes32 _did)
    {
        require(isOwnerProviderOrDelegate(_did),
            'Only owner, provider or delegated'
        );
        _;
    }

    modifier onlyValidAttributes(string memory _attributes)
    {
        require(
            bytes(_attributes).length <= 2048,
            'Invalid attributes size'
        );
        _;
    }

    modifier nftIsInitialized(bytes32 _did)
    {
        require(
            didRegisterList.didRegisters[_did].nftInitialized,
            'NFT not initialized'
        );
        _;
    }    
    
    //////////////////////////////////////////////////////////////
    ////////  EVENTS  ////////////////////////////////////////////
    //////////////////////////////////////////////////////////////

    /**
     * DID Events
     */
    event DIDAttributeRegistered(
        bytes32 indexed _did,
        address indexed _owner,
        bytes32 indexed _checksum,
        string _value,
        address _lastUpdatedBy,
        uint256 _blockNumberUpdated
    );

    event DIDMetadataUpdated(
        bytes32 indexed _did,
        address indexed _owner,
        bytes32 _checksum,
        string _url,
        string _immutableUrl
    );
    
    event DIDProviderRemoved(
        bytes32 _did,
        address _provider,
        bool state
    );

    event DIDProviderAdded(
        bytes32 _did,
        address _provider
    );

    event DIDOwnershipTransferred(
        bytes32 _did,
        address _previousOwner,
        address _newOwner
    );

    event DIDPermissionGranted(
        bytes32 indexed _did,
        address indexed _owner,
        address indexed _grantee
    );

    event DIDPermissionRevoked(
        bytes32 indexed _did,
        address indexed _owner,
        address indexed _grantee
    );

    event DIDProvenanceDelegateRemoved(
        bytes32 _did,
        address _delegate,
        bool state
    );

    event DIDProvenanceDelegateAdded(
        bytes32 _did,
        address _delegate
    );

    /**
     * @notice Register DID attributes.
     *
     * @dev The first attribute of a DID registered sets the DID owner.
     *      Subsequent updates record _checksum and update info.
     *
     * @param _didSeed refers to decentralized identifier seed (a bytes32 length ID). 
     * @param _checksum includes a one-way HASH calculated using the DDO content.
     * @param _url refers to the attribute value, limited to 2048 bytes.
     */
    function registerAttribute(
        bytes32 _didSeed,
        bytes32 _checksum,
        address[] memory _providers,
        string memory _url
    )
    public
    virtual
    {
        registerDID(_didSeed, _checksum, _providers, _url, '', '');
    }


    /**
     * @notice Register DID attributes.
     *
     * @dev The first attribute of a DID registered sets the DID owner.
     *      Subsequent updates record _checksum and update info.
     *
     * @param _didSeed refers to decentralized identifier seed (a bytes32 length ID). 
     *          The final DID will be calculated with the creator address using the `hashDID` function
     * @param _checksum includes a one-way HASH calculated using the DDO content.
     * @param _providers list of addresses that can act as an asset provider     
     * @param _url refers to the url resolving the DID into a DID Document (DDO), limited to 2048 bytes.
     * @param _providers list of DID providers addresses
     * @param _activityId refers to activity
     * @param _immutableUrl refers to url stored in an immutable storage network like IPFS, Filecoin, Arweave
     */
    function registerDID(
        bytes32 _didSeed,
        bytes32 _checksum,
        address[] memory _providers,
        string memory _url,
        bytes32 _activityId,
        string memory _immutableUrl
    )
    public
    virtual
    {
        bytes32 _did = hashDID(_didSeed, _msgSender());
        require(
            didRegisterList.didRegisters[_did].owner == address(0x0),
            'DID already registered'
        );

        didRegisterList.update(_did, _checksum, _url, _msgSender(), _immutableUrl);

        // push providers to storage
        for (uint256 i = 0; i < _providers.length; i++) {
            didRegisterList.addProvider(
                _did,
                _providers[i]
            );
        }

        emit DIDAttributeRegistered(
            _did,
            didRegisterList.didRegisters[_did].owner,
            _checksum,
            _url,
            _msgSender(),
            block.number
        );
        
        _wasGeneratedBy(_did, _did, _msgSender(), _activityId, _immutableUrl);

    }

    function updateMetadataUrl(
        bytes32 _did,
        bytes32 _checksum,
        string memory _url,
        string memory _immutableUrl
    )
    public
    onlyDIDOwner(_did)
    virtual {
        didRegisterList.update(_did, _checksum, _url, _msgSender(), _immutableUrl);
        used(
            keccak256(abi.encode(_did, _checksum, _url, _immutableUrl, block.number, _msgSender())),
            _did,
            _msgSender(),
            keccak256('updateMetadataUrl'),
            '',
            _immutableUrl
        );
        emit DIDMetadataUpdated(
            _did,
            _msgSender(),
            _checksum,
            _url,
            _immutableUrl
        ); 
    }
    
    /**
     * @notice It generates a DID using as seed a bytes32 and the address of the DID creator
     * @param _didSeed refers to DID Seed used as base to generate the final DID
     * @param _creator address of the creator of the DID     
     * @return the new DID created
    */
    function hashDID(
        bytes32 _didSeed, 
        address _creator
    ) 
    public 
    pure 
    returns (bytes32) 
    {
        return keccak256(abi.encode(_didSeed, _creator));
    }
    
    /**
     * @notice areRoyaltiesValid checks if for a given DID and rewards distribution, this allocate the  
     * original creator royalties properly
     * @param _did refers to decentralized identifier (a byte32 length ID)
     * @param _amounts refers to the amounts to reward
     * @param _receivers refers to the receivers of rewards
     * @return true if the rewards distribution respect the original creator royalties
     */
    function areRoyaltiesValid(     
        bytes32 _did,
        uint256[] memory _amounts,
        address[] memory _receivers,
        address _tokenAddress
    )
    public
    view
    returns (bool)
    {
        return didRegisterList.areRoyaltiesValid(_did, _amounts, _receivers, _tokenAddress);
    }
    
    function wasGeneratedBy(
        bytes32 _provId,
        bytes32 _did,
        address _agentId,
        bytes32 _activityId,
        string memory _attributes
    )
    internal
    onlyDIDOwner(_did)
    returns (bool)
    {
        return _wasGeneratedBy(_provId, _did, _agentId, _activityId, _attributes);
    }

    
    function used(
        bytes32 _provId,
        bytes32 _did,
        address _agentId,
        bytes32 _activityId,
        bytes memory _signatureUsing,    
        string memory _attributes
    )
    public
    returns (bool success)
    {
        return _used(
            _provId, _did, _agentId, _activityId, _signatureUsing, _attributes);
    }
    
    
    function wasDerivedFrom(
        bytes32 _provId,
        bytes32 _newEntityDid,
        bytes32 _usedEntityDid,
        address _agentId,
        bytes32 _activityId,
        string memory _attributes
    )
    public
    onlyOwnerProviderOrDelegated(_usedEntityDid)
    returns (bool success)
    {
        return _wasDerivedFrom(
            _provId, _newEntityDid, _usedEntityDid, _agentId, _activityId, _attributes);
    }

    
    function wasAssociatedWith(
        bytes32 _provId,
        bytes32 _did,
        address _agentId,
        bytes32 _activityId,
        string memory _attributes
    )
    public
    onlyOwnerProviderOrDelegated(_did)
    returns (bool success)
    {
        return _wasAssociatedWith(
            _provId, _did, _agentId, _activityId, _attributes);
    }

    
    /**
     * @notice Implements the W3C PROV Delegation action
     * Each party involved in this method (_delegateAgentId & _responsibleAgentId) must provide a valid signature.
     * The content to sign is a representation of the footprint of the event (_did + _delegateAgentId + _responsibleAgentId + _activityId) 
     *
     * @param _provId unique identifier referring to the provenance entry
     * @param _did refers to decentralized identifier (a bytes32 length ID) of the entity
     * @param _delegateAgentId refers to address acting on behalf of the provenance record
     * @param _responsibleAgentId refers to address responsible of the provenance record
     * @param _activityId refers to activity
     * @param _signatureDelegate refers to the digital signature provided by the did delegate.     
     * @param _attributes refers to the provenance attributes
     * @return success true if the action was properly registered
     */
    function actedOnBehalf(
        bytes32 _provId,
        bytes32 _did,
        address _delegateAgentId,
        address _responsibleAgentId,
        bytes32 _activityId,
        bytes memory _signatureDelegate,
        string memory _attributes
    )
    public
    onlyOwnerProviderOrDelegated(_did)
    returns (bool success)
    {
        _actedOnBehalf(
            _provId, _did, _delegateAgentId, _responsibleAgentId, _activityId, _signatureDelegate, _attributes);
        addDIDProvenanceDelegate(_did, _delegateAgentId);
        return true;
    }
    
    
    /**
     * @notice addDIDProvider add new DID provider.
     *
     * @dev it adds new DID provider to the providers list. A provider
     *      is any entity that can serve the registered asset
     * @param _did refers to decentralized identifier (a bytes32 length ID).
     * @param _provider provider's address.
     */
    function addDIDProvider(
        bytes32 _did,
        address _provider
    )
    external
    onlyDIDOwner(_did)
    {
        didRegisterList.addProvider(_did, _provider);

        emit DIDProviderAdded(
            _did,
            _provider
        );
    }

    /**
     * @notice removeDIDProvider delete an existing DID provider.
     * @param _did refers to decentralized identifier (a bytes32 length ID).
     * @param _provider provider's address.
     */
    function removeDIDProvider(
        bytes32 _did,
        address _provider
    )
    external
    onlyDIDOwner(_did)
    {
        bool state = didRegisterList.removeProvider(_did, _provider);

        emit DIDProviderRemoved(
            _did,
            _provider,
            state
        );
    }

    /**
     * @notice addDIDProvenanceDelegate add new DID provenance delegate.
     *
     * @dev it adds new DID provenance delegate to the delegates list. 
     * A delegate is any entity that interact with the provenance entries of one DID
     * @param _did refers to decentralized identifier (a bytes32 length ID).
     * @param _delegate delegates's address.
     */
    function addDIDProvenanceDelegate(
        bytes32 _did,
        address _delegate
    )
    public
    onlyOwnerProviderOrDelegated(_did)
    {
        didRegisterList.addDelegate(_did, _delegate);

        emit DIDProvenanceDelegateAdded(
            _did,
            _delegate
        );
    }

    /**
     * @notice removeDIDProvenanceDelegate delete an existing DID delegate.
     * @param _did refers to decentralized identifier (a bytes32 length ID).
     * @param _delegate delegate's address.
     */
    function removeDIDProvenanceDelegate(
        bytes32 _did,
        address _delegate
    )
    external
    onlyOwnerProviderOrDelegated(_did)
    {
        bool state = didRegisterList.removeDelegate(_did, _delegate);

        emit DIDProvenanceDelegateRemoved(
            _did,
            _delegate,
            state
        );
    }


    /**
     * @notice transferDIDOwnership transfer DID ownership
     * @param _did refers to decentralized identifier (a bytes32 length ID)
     * @param _newOwner new owner address
     */
    function transferDIDOwnership(bytes32 _did, address _newOwner)
    external
    {
        _transferDIDOwnership(_msgSender(), _did, _newOwner);
    }

    function _transferDIDOwnership(address _sender, bytes32 _did, address _newOwner) internal
    {
        require(isDIDOwner(_sender, _did), 'Only owner');

        didRegisterList.updateDIDOwner(_did, _newOwner);

        _wasAssociatedWith(
            keccak256(abi.encode(_did, _sender, 'transferDID', _newOwner, block.number)),
            _did, _newOwner, keccak256('transferDID'), 'transferDID');
        
        emit DIDOwnershipTransferred(
            _did, 
            _sender,
            _newOwner
        );
    }

    /**
     * @dev grantPermission grants access permission to grantee 
     * @param _did refers to decentralized identifier (a bytes32 length ID)
     * @param _grantee address 
     */
    function grantPermission(
        bytes32 _did,
        address _grantee
    )
    external
    onlyDIDOwner(_did)
    {
        _grantPermission(_did, _grantee);
    }

    /**
     * @dev revokePermission revokes access permission from grantee 
     * @param _did refers to decentralized identifier (a bytes32 length ID)
     * @param _grantee address 
     */
    function revokePermission(
        bytes32 _did,
        address _grantee
    )
    external
    onlyDIDOwner(_did)
    {
        _revokePermission(_did, _grantee);
    }

    /**
     * @dev getPermission gets access permission of a grantee
     * @param _did refers to decentralized identifier (a bytes32 length ID)
     * @param _grantee address
     * @return true if grantee has access permission to a DID
     */
    function getPermission(
        bytes32 _did,
        address _grantee
    )
    external
    view
    returns(bool)
    {
        return _getPermission(_did, _grantee);
    }

    /**
     * @notice isDIDProvider check whether a given DID provider exists
     * @param _did refers to decentralized identifier (a bytes32 length ID).
     * @param _provider provider's address.
     */
    function isDIDProvider(
        bytes32 _did,
        address _provider
    )
    public
    view
    returns (bool)
    {
        return didRegisterList.isProvider(_did, _provider);
    }

    function isDIDProviderOrOwner(
        bytes32 _did,
        address _provider
    )
    public
    view
    returns (bool)
    {
        return didRegisterList.isProvider(_did, _provider) || _provider == getDIDOwner(_did);
    }

    /**
    * @param _did refers to decentralized identifier (a bytes32 length ID).
    * @return owner the did owner
    * @return lastChecksum last checksum
    * @return url URL to the DID metadata
    * @return lastUpdatedBy who was the last updating the DID
    * @return blockNumberUpdated In which block was the DID updated
    * @return providers the list of providers
    * @return royalties the royalties amount
    * @return immutableUrl includes the url to the DDO in immutable storage
    * @return nftInitialized if the NFT has been initialized
    */
    function getDIDRegister(
        bytes32 _did
    )
    public
    view
    returns (
        address owner,
        bytes32 lastChecksum,
        string memory url,
        address lastUpdatedBy,
        uint256 blockNumberUpdated,
        address[] memory providers,
        uint256 royalties,
        string memory immutableUrl,
        bool nftInitialized
    )
    {
        owner = didRegisterList.didRegisters[_did].owner;
        lastChecksum = didRegisterList.didRegisters[_did].lastChecksum;
        url = didRegisterList.didRegisters[_did].url;
        lastUpdatedBy = didRegisterList.didRegisters[_did].lastUpdatedBy;
        blockNumberUpdated = didRegisterList
            .didRegisters[_did].blockNumberUpdated;
        providers = didRegisterList.didRegisters[_did].providers;
        royalties = didRegisterList.didRegisters[_did].royalties;
        immutableUrl = didRegisterList.didRegisters[_did].immutableUrl;
        nftInitialized = didRegisterList.didRegisters[_did].nftInitialized;
    }

    function getNFTInfo(
        bytes32 _did
    )
    public
    view
    returns (
        address nftContractAddress,
        bool nftInitialized
    )
    {
        nftContractAddress = didRegisterList.didRegisters[_did].nftContractAddress;
        nftInitialized = didRegisterList.didRegisters[_did].nftInitialized;
    }
    
    /**
     * @param _did refers to decentralized identifier (a bytes32 length ID).
     * @return blockNumberUpdated last modified (update) block number of a DID.
     */
    function getBlockNumberUpdated(bytes32 _did)
    public
    view
    returns (uint256 blockNumberUpdated)
    {
        return didRegisterList.didRegisters[_did].blockNumberUpdated;
    }

    /**
     * @param _did refers to decentralized identifier (a bytes32 length ID).
     * @return didOwner the address of the DID owner.
     */
    function getDIDOwner(bytes32 _did)
    public
    view
    returns (address didOwner)
    {
        return didRegisterList.didRegisters[_did].owner;
    }

    function getDIDRoyaltyRecipient(bytes32 _did)
    public
    view
    returns (address)
    {
        address res = didRegisterList.didRegisters[_did].royaltyRecipient;
        if (res == address(0)) {
            return didRegisterList.didRegisters[_did].creator;
        }
        return res;
    }

    function getDIDRoyaltyScheme(bytes32 _did)
    public
    view
    returns (address)
    {
        return address(didRegisterList.didRegisters[_did].royaltyScheme);
    }

    function getDIDCreator(bytes32 _did)
    public
    view
    returns (address)
    {
        return didRegisterList.didRegisters[_did].creator;
    }

    /**
     * @dev _grantPermission grants access permission to grantee 
     * @param _did refers to decentralized identifier (a bytes32 length ID)
     * @param _grantee address 
     */
    function _grantPermission(
        bytes32 _did,
        address _grantee
    )
    internal
    {
        require(
            _grantee != address(0),
            'Invalid grantee'
        );
        didPermissions[_did][_grantee] = true;
        emit DIDPermissionGranted(
            _did,
            _msgSender(),
            _grantee
        );
    }

    /**
     * @dev _revokePermission revokes access permission from grantee 
     * @param _did refers to decentralized identifier (a bytes32 length ID)
     * @param _grantee address 
     */
    function _revokePermission(
        bytes32 _did,
        address _grantee
    )
    internal
    {
        require(
            didPermissions[_did][_grantee],
            'Grantee already revoked'
        );
        didPermissions[_did][_grantee] = false;
        emit DIDPermissionRevoked(
            _did,
            _msgSender(),
            _grantee
        );
    }

    /**
     * @dev _getPermission gets access permission of a grantee
     * @param _did refers to decentralized identifier (a bytes32 length ID)
     * @param _grantee address 
     * @return true if grantee has access permission to a DID 
     */
    function _getPermission(
        bytes32 _did,
        address _grantee
    )
    internal
    view
    returns(bool)
    {
        return didPermissions[_did][_grantee];
    }


    //// PROVENANCE SUPPORT METHODS

    /**
     * Fetch the complete provenance entry attributes
     * @param _provId refers to the provenance identifier
     * @return did to what DID refers this entry
     * @return relatedDid DID related with the entry
     * @return agentId the agent identifier
     * @return activityId referring to the id of the activity
     * @return agentInvolvedId agent involved with the action
     * @return method the w3c provenance method
     * @return createdBy who is creating this entry
     * @return blockNumberUpdated in which block was updated
     * @return signature digital signature 
     * 
     */
    function getProvenanceEntry(
        bytes32 _provId
    )
    public
    view
    returns (     
        bytes32 did,
        bytes32 relatedDid,
        address agentId,
        bytes32 activityId,
        address agentInvolvedId,
        uint8   method,
        address createdBy,
        uint256 blockNumberUpdated,
        bytes memory signature
    )
    {
        did = provenanceRegistry.list[_provId].did;
        relatedDid = provenanceRegistry.list[_provId].relatedDid;
        agentId = provenanceRegistry.list[_provId].agentId;
        activityId = provenanceRegistry.list[_provId].activityId;
        agentInvolvedId = provenanceRegistry.list[_provId].agentInvolvedId;
        method = provenanceRegistry.list[_provId].method;
        createdBy = provenanceRegistry.list[_provId].createdBy;
        blockNumberUpdated = provenanceRegistry
            .list[_provId].blockNumberUpdated;
        signature = provenanceRegistry.list[_provId].signature;
    }

    /**
     * @notice isDIDOwner check whether a given address is owner for a DID
     * @param _address user address.
     * @param _did refers to decentralized identifier (a bytes32 length ID).
     */
    function isDIDOwner(
        address _address,
        bytes32 _did
    )
    public
    view
    returns (bool)
    {
        return _address == didRegisterList.didRegisters[_did].owner;
    }


    /**
     * @notice isOwnerProviderOrDelegate check whether _msgSender() is owner, provider or
     * delegate for a DID given
     * @param _did refers to decentralized identifier (a bytes32 length ID).
     * @return boolean true if yes
     */
    function isOwnerProviderOrDelegate(
        bytes32 _did
    )
    public
    view
    returns (bool)
    {
        return (_msgSender() == didRegisterList.didRegisters[_did].owner ||
                    isProvenanceDelegate(_did, _msgSender()) ||
                    isDIDProvider(_did, _msgSender()));
    }    
    
    /**
     * @notice isProvenanceDelegate check whether a given DID delegate exists
     * @param _did refers to decentralized identifier (a bytes32 length ID).
     * @param _delegate delegate's address.
     * @return boolean true if yes     
     */
    function isProvenanceDelegate(
        bytes32 _did,
        address _delegate
    )
    public
    view
    returns (bool)
    {
        return didRegisterList.isDelegate(_did, _delegate);
    }

    /**
     * @param _did refers to decentralized identifier (a bytes32 length ID).
     * @return provenanceOwner the address of the Provenance owner.
     */
    function getProvenanceOwner(bytes32 _did)
    public
    view
    returns (address provenanceOwner)
    {
        return provenanceRegistry.list[_did].createdBy;
    }
    
}

