/*
 * SPDX-License-Identifier: Apache-2.0
 */
pragma solidity >=0.8;

import "./OwnableUpgradeable.sol";
import "./ICrossChainVerifier.sol";

abstract contract CbcDecVer is OwnableUpgradeable {
    // Address of verifier contract to be used for a certain blockchain id.
    mapping(uint256 => ICrossChainVerifier) public verifiers;

    // Address of CrossChain Control Contract on another blockchain.
    mapping(uint256 => address) public remoteCrossChainControlContracts;

    function addVerifier(
        uint256 _blockchainId,
        address _verifier
    ) external onlyOwner {
        require(_blockchainId != 0, "Invalid blockchain id");
        require(_verifier != address(0), "Invalid verifier address");
        verifiers[_blockchainId] = ICrossChainVerifier(_verifier);
    }

    function addRemoteCrossChainControl(
        uint256 _blockchainId,
        address _cbc
    ) external onlyOwner {
        remoteCrossChainControlContracts[_blockchainId] = _cbc;
    }

    /**
     * Decode signatures or proofs and use them to verify an event.
     *
     * @param _blockchainId The blockchain that the event was emitted on.
     * @param _cbcAddress The CrossChain Control Contract that emitted the event.
     * @param _eventFunctionSignature The function selector of the event that emitted the event.
     * @param _eventData The emitted event data.
     * @param _signature The signature of proof across the ABI encoded combination of:
     *            _blockchainId, _cbcAddress, _eventFunctionSignature, and _signature.
     */
    function decodeAndVerifyEvent(
        uint256 _blockchainId,
        address _cbcAddress,
        bytes32 _eventFunctionSignature,
        bytes calldata _eventData,
        bytes calldata _signature
    ) internal view {
        // This indirectly checks that _blockchainId is an authorised source blockchain
        // by checking that there is a verifier for the blockchain.
        ICrossChainVerifier verifier = verifiers[_blockchainId];
        require(
            address(verifier) != address(0),
            "No registered verifier for blockchain"
        );

        require(
            _cbcAddress == remoteCrossChainControlContracts[_blockchainId],
            "Data not emitted by approved contract"
        );

        bytes memory encodedEvent = abi.encodePacked(
            _blockchainId,
            _cbcAddress,
            _eventFunctionSignature,
            _eventData
        );
        verifier.decodeAndVerifyEvent(
            _blockchainId,
            _eventFunctionSignature,
            encodedEvent,
            _signature
        );
    }
}

