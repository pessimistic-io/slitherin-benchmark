pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import "./Condition.sol";
import "./DIDRegistry.sol";
import "./IAccessControl.sol";
import "./AgreementStoreManager.sol";

/**
 * @title Access Condition
 * @author Nevermined
 *
 * @dev Implementation of the Access Condition
 *
 *      Access Secret Store Condition is special condition
 *      where a client or Parity secret store can encrypt/decrypt documents 
 *      based on the on-chain granted permissions. For a given DID 
 *      document, and agreement ID, the owner/provider of the DID 
 *      will fulfill the condition. Consequently secret store 
 *      will check whether the permission is granted for the consumer
 *      in order to encrypt/decrypt the document.
 */
contract AccessCondition is Condition, IAccessControl {

    bytes32 constant public CONDITION_TYPE = keccak256('AccessCondition');

    struct DocumentPermission {
        bytes32 agreementIdDeprecated;
        mapping(address => bool) permission;
    }

    mapping(bytes32 => DocumentPermission) private documentPermissions;
    AgreementStoreManager private agreementStoreManager;
    DIDRegistry private didRegistry;

    event Fulfilled(
        bytes32 indexed _agreementId,
        bytes32 indexed _documentId,
        address indexed _grantee,
        bytes32 _conditionId
    );
    
    modifier onlyDIDOwnerOrProvider(
        bytes32 _documentId
    )
    {
        require(
            didRegistry.isDIDProviderOrOwner(_documentId, _msgSender()),
            'Invalid DID owner/provider'
        );
        _;
    }

   /**
    * @notice initialize init the 
    *       contract with the following parameters
    * @dev this function is called only once during the contract
    *       initialization.
    * @param _owner contract's owner account address
    * @param _conditionStoreManagerAddress condition store manager address
    * @param _agreementStoreManagerAddress agreement store manager address
    */
    function initialize(
        address _owner,
        address _conditionStoreManagerAddress,
        address _agreementStoreManagerAddress
    )
        external
        initializer()
    {
        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);

        conditionStoreManager = ConditionStoreManager(
            _conditionStoreManagerAddress
        );

        agreementStoreManager = AgreementStoreManager(
            _agreementStoreManagerAddress
        );
        didRegistry = DIDRegistry(
            agreementStoreManager.getDIDRegistryAddress()
        );
        
    }

    /**
     * Should be called when the contract has been upgraded.
     */
    function reinitialize() external reinitializer(2) {
        didRegistry = DIDRegistry(
            agreementStoreManager.getDIDRegistryAddress()
        );
    }

   /**
    * @notice hashValues generates the hash of condition inputs 
    *        with the following parameters
    * @param _documentId refers to the DID in which secret store will issue the decryption keys
    * @param _grantee is the address of the granted user or the DID provider
    * @return bytes32 hash of all these values 
    */
    function hashValues(
        bytes32 _documentId,
        address _grantee
    )
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(_documentId, _grantee));
    }

   /**
    * @notice fulfill access secret store condition
    * @dev only DID owner or DID provider can call this
    *       method. Fulfill method sets the permissions 
    *       for the granted consumer's address to true then
    *       fulfill the condition
    * @param _agreementId agreement identifier
    * @param _documentId refers to the DID in which secret store will issue the decryption keys
    * @param _grantee is the address of the granted user or the DID provider
    * @return condition state (Fulfilled/Aborted)
    */
    function fulfill(
        bytes32 _agreementId,
        bytes32 _documentId,
        address _grantee
    )
        public
        returns (ConditionStoreLibrary.ConditionState)
    {
        grantPermission(
            _grantee,
            _documentId
        );
        
        bytes32 _id = generateId(
            _agreementId,
            hashValues(_documentId, _grantee)
        );

        ConditionStoreLibrary.ConditionState state = super.fulfillWithProvenance(
            _id,
            ConditionStoreLibrary.ConditionState.Fulfilled,
            _documentId,
            'AccessCondition',
            _msgSender()
        );
        
        emit Fulfilled(
            _agreementId,
            _documentId,
            _grantee,
            _id
        );

        return state;
    }
    
   /**
    * @notice grantPermission is called only by DID owner or provider
    * @param _grantee is the address of the granted user or the DID provider
    * @param _documentId refers to the DID in which secret store will issue the decryption keys
    */
    function grantPermission(
        address _grantee,
        bytes32 _documentId
        
    )
        public
        override
        onlyDIDOwnerOrProvider(_documentId)
    {
        documentPermissions[_documentId].permission[_grantee] = true;
    }

   /**
    * @notice renouncePermission is called only by DID owner or provider
    * @param _grantee is the address of the granted user or the DID provider
    * @param _documentId refers to the DID in which secret store will issue the decryption keys
    */
    function renouncePermission(
        address _grantee,
        bytes32 _documentId
    )
        public
        override
        onlyDIDOwnerOrProvider(_documentId)
    {
        documentPermissions[_documentId].permission[_grantee] = false;
    }
    
   /**
    * @notice checkPermissions is called by Parity secret store
    * @param _documentId refers to the DID in which secret store will issue the decryption keys
    * @param _grantee is the address of the granted user or the DID provider
    * @return permissionGranted true if the access was granted
    */
    function checkPermissions(
        address _grantee,
        bytes32 _documentId
    )
        external view
        override
        returns(bool permissionGranted)
    {
        return (
            didRegistry.isDIDProvider(_documentId, _grantee) ||
            didRegistry.isDIDOwner(_grantee, _documentId) ||
            documentPermissions[_documentId].permission[_grantee] ||
            didRegistry.getPermission(_documentId, _grantee)
        );
    }
}


