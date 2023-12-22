pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import "./OwnableUpgradeable.sol";
import "./INVMConfig.sol";
import "./Common.sol";

/**
 * @title Provenance Registry Library
 * @author Nevermined
 *
 * @dev All function calls are currently implemented without side effects
 */
/* solium-disable-next-line */
abstract contract ProvenanceRegistry is CommonOwnable, AccessControlUpgradeable {

    // solhint-disable-next-line
    function __ProvenanceRegistry_init() internal initializer {
        __Context_init_unchained();
        __ProvenanceRegistry_init_unchained();
    }

    // solhint-disable-next-line
    function __ProvenanceRegistry_init_unchained() internal initializer {
    }
    
    // Provenance Entity
    struct Provenance {
        // DID associated to this provenance event
        bytes32 did;
        // DID created or associated to the original one triggered on this provenance event
        bytes32 relatedDid;
        // Agent associated to the provenance event
        address agentId;
        // Provenance activity
        bytes32 activityId;
        // Agent involved in the provenance event beyond the agent id
        address agentInvolvedId;
        // W3C PROV method
        uint8   method;
        // Who added this event to the registry
        address createdBy;
        // Block number of when it was added
        uint256 blockNumberUpdated;
        // Signature of the delegate
        bytes   signature;  
    }

    // List of Provenance entries registered in the system
    struct ProvenanceRegistryList {
        mapping(bytes32 => Provenance) list;
    }
    
    ProvenanceRegistryList internal provenanceRegistry;
    
    // W3C Provenance Methods
    enum ProvenanceMethod {
        ENTITY,
        ACTIVITY,
        WAS_GENERATED_BY,
        USED,
        WAS_INFORMED_BY,
        WAS_STARTED_BY,
        WAS_ENDED_BY,
        WAS_INVALIDATED_BY,
        WAS_DERIVED_FROM,
        AGENT,
        WAS_ATTRIBUTED_TO,
        WAS_ASSOCIATED_WITH,
        ACTED_ON_BEHALF
    }

    /**
    * Provenance Events
    */
    event ProvenanceAttributeRegistered(
        bytes32 indexed provId,
        bytes32 indexed _did,
        address indexed _agentId,
        bytes32 _activityId,
        bytes32 _relatedDid,
        address _agentInvolvedId,
        ProvenanceMethod _method,
        string _attributes,
        uint256 _blockNumberUpdated
    );

    ///// EVENTS ///////
    
    event WasGeneratedBy(
        bytes32 indexed _did,
        address indexed _agentId,
        bytes32 indexed _activityId,
        bytes32 provId,
        string _attributes,
        uint256 _blockNumberUpdated
    );


    event Used(
        bytes32 indexed _did,
        address indexed _agentId,
        bytes32 indexed _activityId,
        bytes32 provId,
        string _attributes,
        uint256 _blockNumberUpdated
    );

    event WasDerivedFrom(
        bytes32 indexed _newEntityDid,
        bytes32 indexed _usedEntityDid,
        address indexed _agentId,
        bytes32 _activityId,
        bytes32 provId,
        string _attributes,
        uint256 _blockNumberUpdated
    );

    event WasAssociatedWith(
        bytes32 indexed _entityDid,
        address indexed _agentId,
        bytes32 indexed _activityId,
        bytes32 provId,
        string _attributes,
        uint256 _blockNumberUpdated
    );

    event ActedOnBehalf(
        bytes32 indexed _entityDid,
        address indexed _delegateAgentId,
        address indexed _responsibleAgentId,
        bytes32 _activityId,
        bytes32 provId,
        string _attributes,
        uint256 _blockNumberUpdated
    );

    function _provenanceStorage() virtual internal returns (bool);

    /**
     * @notice create an event in the Provenance store
     * @dev access modifiers and storage pointer should be implemented in ProvenanceRegistry
     * @param _provId refers to provenance event identifier
     * @param _did refers to decentralized identifier (a byte32 length ID)
     * @param _relatedDid refers to decentralized identifier (a byte32 length ID) of a related entity
     * @param _agentId refers to address of the agent creating the provenance record
     * @param _activityId refers to activity
     * @param _agentInvolvedId refers to address of the agent involved with the provenance record     
     * @param _method refers to the W3C Provenance method
     * @param _createdBy refers to address of the agent triggering the activity
     * @param _signatureDelegate refers to the digital signature provided by the did delegate. 
    */
    function createProvenanceEntry(
        bytes32 _provId,
        bytes32 _did,
        bytes32 _relatedDid,
        address _agentId,
        bytes32 _activityId,
        address _agentInvolvedId,
        ProvenanceMethod   _method,
        address _createdBy,
        bytes  memory _signatureDelegate,
        string memory _attributes
    )
    internal
    {

        if (!_provenanceStorage()) {
            return;
        }

        require(
            provenanceRegistry.list[_provId].createdBy == address(0x0),
            'Already existing provId'
        );

        provenanceRegistry.list[_provId] = Provenance({
            did: _did,
            relatedDid: _relatedDid,
            agentId: _agentId,
            activityId: _activityId,
            agentInvolvedId: _agentInvolvedId,
            method: uint8(_method),
            createdBy: _createdBy,
            blockNumberUpdated: block.number,
            signature: _signatureDelegate
        });

        /* emitting _attributes here to avoid expensive storage */
        emit ProvenanceAttributeRegistered(
            _provId,
            _did, 
            _agentId,
            _activityId,
            _relatedDid,
            _agentInvolvedId,
            _method,
            _attributes,
            block.number
        );
        
    }


    /**
     * @notice Implements the W3C PROV Generation action
     *
     * @param _provId unique identifier referring to the provenance entry     
     * @param _did refers to decentralized identifier (a bytes32 length ID) of the entity created
     * @param _agentId refers to address of the agent creating the provenance record
     * @param _activityId refers to activity
     * @param _attributes refers to the provenance attributes
     * @return the number of the new provenance size
     */
    function _wasGeneratedBy(
        bytes32 _provId,
        bytes32 _did,
        address _agentId,
        bytes32 _activityId,
        string memory _attributes
    )
    internal
    virtual
    returns (bool)
    {
        
        createProvenanceEntry(
            _provId,
            _did,
            '',
            _agentId,
            _activityId,
            address(0x0),
            ProvenanceMethod.WAS_GENERATED_BY,
            _msgSender(),
            new bytes(0), // No signatures between parties needed
            _attributes
        );

        emit WasGeneratedBy(
            _did,
           _msgSender(),
            _activityId,
            _provId,
            _attributes,
            block.number
        );

        return true;
    }

    /**
     * @notice Implements the W3C PROV Usage action
     *
     * @param _provId unique identifier referring to the provenance entry     
     * @param _did refers to decentralized identifier (a bytes32 length ID) of the entity created
     * @param _agentId refers to address of the agent creating the provenance record
     * @param _activityId refers to activity
     * @param _signatureUsing refers to the digital signature provided by the agent using the _did     
     * @param _attributes refers to the provenance attributes
     * @return success true if the action was properly registered
    */
    function _used(
        bytes32 _provId,
        bytes32 _did,
        address _agentId,
        bytes32 _activityId,
        bytes memory _signatureUsing,
        string memory _attributes
    )
    internal
    virtual
    returns (bool success)
    {

        createProvenanceEntry(
            _provId,
            _did,
            '',
            _agentId,
            _activityId,
            address(0x0),
            ProvenanceMethod.USED,
            _msgSender(),
            _signatureUsing,
            _attributes
        );
        
        emit Used(
            _did,
            _agentId,
            _activityId,
            _provId,
            _attributes,
            block.number
        );

        return true;
    }


    /**
     * @notice Implements the W3C PROV Derivation action
     *
     * @param _provId unique identifier referring to the provenance entry     
     * @param _newEntityDid refers to decentralized identifier (a bytes32 length ID) of the entity created
     * @param _usedEntityDid refers to decentralized identifier (a bytes32 length ID) of the entity used to derive the new did
     * @param _agentId refers to address of the agent creating the provenance record
     * @param _activityId refers to activity
     * @param _attributes refers to the provenance attributes
     * @return success true if the action was properly registered
     */
    function _wasDerivedFrom(
        bytes32 _provId,
        bytes32 _newEntityDid,
        bytes32 _usedEntityDid,
        address _agentId,
        bytes32 _activityId,
        string memory _attributes
    )
    internal
    virtual
    returns (bool success)
    {

        createProvenanceEntry(
            _provId,
            _newEntityDid,
            _usedEntityDid,
            _agentId,
            _activityId,
            address(0x0),
            ProvenanceMethod.WAS_DERIVED_FROM,
            _msgSender(),
            new bytes(0), // No signatures between parties needed
            _attributes
        );

        emit WasDerivedFrom(
            _newEntityDid,
            _usedEntityDid,
            _agentId,
            _activityId,
            _provId,
            _attributes,
            block.number
        );

        return true;
    }

    /**
     * @notice Implements the W3C PROV Association action
     *
     * @param _provId unique identifier referring to the provenance entry     
     * @param _did refers to decentralized identifier (a bytes32 length ID) of the entity
     * @param _agentId refers to address of the agent creating the provenance record
     * @param _activityId refers to activity
     * @param _attributes refers to the provenance attributes
     * @return success true if the action was properly registered
    */
    function _wasAssociatedWith(
        bytes32 _provId,
        bytes32 _did,
        address _agentId,
        bytes32 _activityId,
        string memory _attributes
    )
    internal
    virtual
    returns (bool success)
    {
        
        createProvenanceEntry(
            _provId,
            _did,
            '',
            _agentId,
            _activityId,
            address(0x0),
            ProvenanceMethod.WAS_ASSOCIATED_WITH,
            _msgSender(),
            new bytes(0), // No signatures between parties needed
            _attributes
        );

        emit WasAssociatedWith(
            _did,
            _agentId,
            _activityId,
            _provId,
            _attributes,
            block.number
        );

        return true;
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
    function _actedOnBehalf(
        bytes32 _provId,
        bytes32 _did,
        address _delegateAgentId,
        address _responsibleAgentId,
        bytes32 _activityId,
        bytes memory _signatureDelegate,
        string memory _attributes
    )
    internal
    virtual
    returns (bool success)
    {

        createProvenanceEntry(
            _provId,
            _did,
            '',
            _delegateAgentId,
            _activityId,
            _responsibleAgentId,
            ProvenanceMethod.ACTED_ON_BEHALF,
            _msgSender(),
            _signatureDelegate,
            _attributes
        );
        
        emit ActedOnBehalf(
            _did,
            _delegateAgentId,
            _responsibleAgentId,
            _activityId,
            _provId,
            _attributes,
            block.number
        );

        return true;
    }

    function _msgSender() internal override(CommonOwnable,ContextUpgradeable) virtual view returns (address ret) {
        return Common._msgSender();
    }
    function _msgData() internal override(CommonOwnable,ContextUpgradeable) virtual view returns (bytes calldata ret) {
        return Common._msgData();
    }    
}

