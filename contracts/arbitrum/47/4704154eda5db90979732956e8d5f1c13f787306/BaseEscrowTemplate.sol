pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import "./AgreementTemplate.sol";
import "./DIDRegistry.sol";

contract BaseEscrowTemplate is AgreementTemplate {

    AgreementData internal agreementData;

    event AgreementCreated(
        bytes32 indexed _agreementId,
        bytes32 _did,
        address indexed _accessConsumer,
        address indexed _accessProvider,
        uint[]  _timeLocks,
        uint[]  _timeOuts,
        bytes32[] _conditionIdSeeds,
        bytes32[] _conditionIds,
        bytes32 _idSeed,
        address _creator
    );

    struct AgreementDataModel {
        address accessConsumer;
        address accessProvider;
        bytes32 did;
    }

    struct AgreementData {
        mapping(bytes32 => AgreementDataModel) agreementDataItems;
        bytes32[] agreementIds;
    }

   /**
    * @notice createAgreement creates agreements through agreement template
    * @dev this function initializes the agreement by setting the DID,
    *       conditions ID, timeouts, time locks and the consumer address.
    *       The DID provider/owner is automatically detected by the DID
    *       Registry
    * @param _id SEA agreement unique identifier
    * @param _did Decentralized Identifier (DID)
    * @param _conditionIds conditions ID associated with the condition types
    * @param _timeLocks the starting point of the time window ,time lock is 
    *       in block number not seconds
    * @param _timeOuts the ending point of the time window ,time lock is 
    *       in block number not seconds
    * @param _accessConsumer consumer address
    */
    function createAgreement(
        bytes32 _id,
        bytes32 _did,
        bytes32[] memory _conditionIds,
        uint[] memory _timeLocks,
        uint[] memory _timeOuts,
        address _accessConsumer
    )
        public
    {
        super.createAgreement(
            _id,
            _did,
            _conditionIds,
            _timeLocks,
            _timeOuts
        );
        _initAgreement(_id, _did, _timeLocks, _timeOuts, _accessConsumer, _conditionIds);
    }

    function createAgreementAndPayEscrow(
        bytes32 _id,
        bytes32 _did,
        bytes32[] memory _conditionIds,
        uint[] memory _timeLocks,
        uint[] memory _timeOuts,
        address _accessConsumer,
        uint _idx,
        address payable _rewardAddress,
        address _tokenAddress,
        uint256[] memory _amounts,
        address[] memory _receivers
    )
        public
        payable
    {
        super.createAgreementAndPay(
            _id,
            _did,
            _conditionIds,
            _timeLocks,
            _timeOuts,
            _idx,
            _rewardAddress,
            _tokenAddress,
            _amounts,
            _receivers
        );
        _initAgreement(_id, _did, _timeLocks, _timeOuts, _accessConsumer, _conditionIds);
    }

    function createAgreementAndFulfill(
        bytes32 _id,
        bytes32 _did,
        bytes32[] memory _conditionIds,
        uint[] memory _timeLocks,
        uint[] memory _timeOuts,
        address _accessConsumer,
        uint[] memory _indices,
        address[] memory _accounts,
        bytes[] memory _params
    )
        internal
    {
        super.createAgreementAndFulfill(_id, _did, _conditionIds, _timeLocks, _timeOuts, _indices, _accounts, _params);
        _initAgreement(_id, _did, _timeLocks, _timeOuts, _accessConsumer, _conditionIds);
    }

    function _makeIds(
        bytes32 _idSeed,
        bytes32[] memory _conditionIds
    )
    internal view returns (bytes32[] memory)
    {
        bytes32 _id = keccak256(abi.encode(_idSeed, _msgSender()));
        bytes32[] memory ids = new bytes32[](_conditionIds.length);
        for (uint i = 0; i < ids.length; i++) {
            ids[i] = keccak256(abi.encode(_id, conditionTypes[i], _conditionIds[i]));
        }
        return ids;
    }

    function _initAgreement(
        bytes32 _idSeed,
        bytes32 _did,
        uint[] memory _timeLocks,
        uint[] memory _timeOuts,
        address _accessConsumer,
        bytes32[] memory _conditionIds
    )
        internal
    {

        bytes32 _id = keccak256(abi.encode(_idSeed, _msgSender()));
        // storing some additional information for the template
        agreementData.agreementDataItems[_id].accessConsumer = _accessConsumer;
        agreementData.agreementDataItems[_id].did = _did;

        emit AgreementCreated(
            _id,
            _did,
            agreementData.agreementDataItems[_id].accessConsumer,
            agreementData.agreementDataItems[_id].accessProvider,
            _timeLocks,
            _timeOuts,
            _conditionIds,
            _makeIds(_idSeed, _conditionIds),
            _idSeed,
            _msgSender()
        );

    }

    /**
    * @notice getAgreementData return the agreement Data
    * @param _id SEA agreement unique identifier
    * @return accessConsumer the agreement consumer
    * @return accessProvider the provider addresses
    */
    function getAgreementData(bytes32 _id)
        external
        view
        returns (
            address accessConsumer,
            address accessProvider,
            bytes32 did
        )
    {
        address owner = address(0);
        address[] memory providers;
        
        
        DIDRegistry didRegistryInstance = DIDRegistry(
            agreementStoreManager.getDIDRegistryAddress()
        );
        
        (owner, , , , , providers,,,) = didRegistryInstance.getDIDRegister(agreementData.agreementDataItems[_id].did);

        if (providers.length > 0) {
            accessProvider = providers[0];
        } else {
            accessProvider = owner;
        }
        accessConsumer = agreementData.agreementDataItems[_id].accessConsumer;
        did = agreementData.agreementDataItems[_id].did;
    }
}

