pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import "./AgreementStoreLibrary.sol";
import "./ConditionStoreManager.sol";
import "./ICondition.sol";
import "./DIDRegistry.sol";
import "./TemplateStoreManager.sol";

import "./OwnableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";

interface Template {
    function getConditionTypes() external view returns (address[] memory);
}

/**
 * @title Agreement Store Manager
 * @author Nevermined
 *
 * @dev Implementation of the Agreement Store.
 *
 *      The agreement store generates conditions for an agreement template.
 *      Agreement templates must to be approved in the Template Store
 *      Each agreement is linked to the DID of an asset.
 */
contract AgreementStoreManager is CommonAccessControl {

    bytes32 private constant PROXY_ROLE = keccak256('PROXY_ROLE');

    function grantProxyRole(address _address) public onlyOwner {
        grantRole(PROXY_ROLE, _address);
    }

    function revokeProxyRole(address _address) public onlyOwner {
        revokeRole(PROXY_ROLE, _address);
    }

    /**
     * @dev The Agreement Store Library takes care of the basic storage functions
     */
    using AgreementStoreLibrary for AgreementStoreLibrary.AgreementList;

    /**
     * @dev state storage for the agreements
     */
    AgreementStoreLibrary.AgreementList internal agreementList;

    ConditionStoreManager internal conditionStoreManager;
    TemplateStoreManager internal templateStoreManager;
    DIDRegistry internal didRegistry;

    /**
     * @dev initialize AgreementStoreManager Initializer
     *      Initializes Ownable. Only on contract creation.
     * @param _owner refers to the owner of the contract
     * @param _conditionStoreManagerAddress is the address of the connected condition store
     * @param _templateStoreManagerAddress is the address of the connected template store
     * @param _didRegistryAddress is the address of the connected DID Registry
     */
    function initialize(
        address _owner,
        address _conditionStoreManagerAddress,
        address _templateStoreManagerAddress,
        address _didRegistryAddress
    )
        public
        initializer
    {
        require(
            _owner != address(0) &&
            _conditionStoreManagerAddress != address(0) &&
            _templateStoreManagerAddress != address(0) &&
            _didRegistryAddress != address(0),
            'Invalid address'
        );
        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);
        
        conditionStoreManager = ConditionStoreManager(
            _conditionStoreManagerAddress
        );
        templateStoreManager = TemplateStoreManager(
            _templateStoreManagerAddress
        );
        didRegistry = DIDRegistry(
            _didRegistryAddress
        );
        _setupRole(DEFAULT_ADMIN_ROLE, _owner);

    }

    function fullConditionId(
        bytes32 _agreementId,
        address _condType,
        bytes32 _valueHash
    )
        public
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                _agreementId,
                _condType,
                _valueHash
            )
        );
    }
    function agreementId(
        bytes32 _agreementId,
        address _creator
    )
        public
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                _agreementId,
                _creator
            )
        );
    }
    
    /**
     * @dev Create a new agreement.
     *      The agreement will create conditions of conditionType with conditionId.
     *      Only "approved" templates can access this function.
     * @param _id is the ID of the new agreement. Must be unique.
     * @param _did is the bytes32 DID of the asset. The DID must be registered beforehand.
     * @param _conditionTypes is a list of addresses that point to Condition contracts.
     * @param _conditionIds is a list of bytes32 content-addressed Condition IDs
     * @param _timeLocks is a list of uint time lock values associated to each Condition
     * @param _timeOuts is a list of uint time out values associated to each Condition
     */
    function createAgreement(
        bytes32 _id,
        bytes32 _did,
        address[] memory _conditionTypes,
        bytes32[] memory _conditionIds,
        uint[] memory _timeLocks,
        uint[] memory _timeOuts
    )
        public
    {
        require(
            templateStoreManager.isTemplateApproved(_msgSender()) == true,
            'Template not Approved'
        );
        require(
            didRegistry.getBlockNumberUpdated(_did) > 0,
            'DID not registered'
        );
        require(
            _conditionIds.length == _conditionTypes.length &&
            _timeLocks.length == _conditionTypes.length &&
            _timeOuts.length == _conditionTypes.length,
            'Arguments have wrong length'
        );

        // create the conditions in condition store. Fail if conditionId already exists.
        for (uint256 i = 0; i < _conditionTypes.length; i++) {
            conditionStoreManager.createCondition(
                fullConditionId(_id, _conditionTypes[i], _conditionIds[i]),
                _conditionTypes[i],
                _timeLocks[i],
                _timeOuts[i]
            );
        }
        agreementList.create(
            _id,
            _msgSender()
        );
    }

    struct CreateAgreementArgs {
        bytes32 _id;
        bytes32 _did;
        address[] _conditionTypes;
        bytes32[] _conditionIds;
        uint[] _timeLocks;
        uint[] _timeOuts;
        address _creator;
        uint _idx;
        address payable _rewardAddress;
        address _tokenAddress;
        uint256[] _amounts;
        address[] _receivers;
    }

    function createAgreementAndPay(CreateAgreementArgs memory args)
        public payable
    {
        address[] memory _account = new address[](1);
        _account[0] = args._creator;
        uint[] memory indices = new uint[](1);
        indices[0] = args._idx;
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(args._did, args._rewardAddress, args._tokenAddress, args._amounts, args._receivers);
        createAgreementAndFulfill(args._id, args._did, args._conditionTypes, args._conditionIds, args._timeLocks, args._timeOuts, _account, indices, params);
    }

    function createAgreementAndFulfill(
        bytes32 _id,
        bytes32 _did,
        address[] memory _conditionTypes,
        bytes32[] memory _conditionIds,
        uint[] memory _timeLocks,
        uint[] memory _timeOuts,
        address[] memory _account,
        uint[] memory _idx,
        bytes[] memory params
    )
        public payable
    {
        require(hasRole(PROXY_ROLE, _msgSender()), 'Proxy role required');
        createAgreement(_id, _did, _conditionTypes, _conditionIds, _timeLocks, _timeOuts);
        if (_idx.length > 0) {
            ICondition(_conditionTypes[_idx[0]]).fulfillProxy{value: msg.value}(_account[0], _id, params[0]);
        }
        for (uint i = 1; i < _idx.length; i++) {
            ICondition(_conditionTypes[_idx[i]]).fulfillProxy(_account[i], _id, params[i]);
        }
    }

    function getAgreementTemplate(bytes32 _id)
        external
        view
        returns (address)
    {
        return agreementList.agreements[_id].templateId;
    }

    /**
     * @dev getDIDRegistryAddress utility function 
     * used by other contracts or any EOA.
     * @return the DIDRegistry address
     */
    function getDIDRegistryAddress()
        public
        virtual
        view
        returns(address)
    {
        return address(didRegistry);
    }

    /**
     * @dev getNvmConfigAddress get the address of the NeverminedConfig contract
     * @return NeverminedConfig contract address
     */
    function getNvmConfigAddress()
    public
    override
    view
    returns (address)
    {
        if (address(didRegistry) == address(0)) {
            return address(0);
        }
        return didRegistry.getNvmConfigAddress();
    }
}

