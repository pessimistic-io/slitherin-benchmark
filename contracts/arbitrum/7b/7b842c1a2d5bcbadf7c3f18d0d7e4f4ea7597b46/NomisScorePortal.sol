// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { AbstractPortal } from "./AbstractPortal.sol";
import { AttestationPayload } from "./Structs.sol";
import { Ownable } from "./Ownable.sol";
import { Pausable } from "./Pausable.sol";

///////////////////////////////////////////////////////////////
//  ___   __    ______   ___ __ __    ________  ______       //
// /__/\ /__/\ /_____/\ /__//_//_/\  /_______/\/_____/\      //
// \::\_\\  \ \\:::_ \ \\::\| \| \ \ \__.::._\/\::::_\/_     //
//  \:. `-\  \ \\:\ \ \ \\:.      \ \   \::\ \  \:\/___/\    //
//   \:. _    \ \\:\ \ \ \\:.\-/\  \ \  _\::\ \__\_::._\:\   //
//    \. \`-\  \ \\:\_\ \ \\. \  \  \ \/__\::\__/\ /____\:\  //
//     \__\/ \__\/ \_____\/ \__\/ \__\/\________\/ \_____\/  //
//                                                           //
///////////////////////////////////////////////////////////////

/**
 * @title NomisScore Portal
 * @author Nomis Labs
 * @notice This is an NomisScore portal, able to attest data on Verax.
 * @custom:security-contact info@nomis.cc
 */
contract NomisScorePortal is 
    Ownable,
    Pausable,
    AbstractPortal
{
    /*#########################
    ##        Structs        ##
    ##########################*/

    /**
     * @dev Attestation request data struct.
     * @param expirationTime The expiration time of the attestation.
     * @param revocable Whether the attestation is revocable or not.
     * @param tokenId The token id of the minted NomisScore.
     * @param updated The timestamp of the mint or last update of the NomisScore.
     * @param value The score value of the NomisScore.
     * @param chainId The chain id of the NomisScore.
     * @param calcModel The scoring calculation model of the NomisScore.
     */
    struct AttestationRequestData {
        uint64 expirationTime;
        bool revocable;
        uint256 tokenId;
        uint256 updated;
        uint16 value;
        uint256 chainId;
        uint16 calcModel;
    }

    /**
     * @dev Attestation request struct.
     * @param schema The schema to attest.
     * @param data The attestation data.
     */
    struct AttestationRequest {
        bytes32 schema;
        AttestationRequestData data;
    }

    /*#########################
    ##        Errors         ##
    ##########################*/

    /// @dev Error thrown when the withdraw fails.
    error WithdrawFail();

    /// @dev Error thrown when the attestation is expired.
    error AttestationExpired();

    /*#########################
    ##         Events        ##
    ##########################*/

    /**
     * @dev Event emitted when a NomisScore is attested.
     * @param schema The schema to attest.
     * @param expirationTime The expiration time of the attestation.
     * @param tokenId The token id of the minted NomisScore.
     * @param updated The timestamp of the mint or last update of the NomisScore.
     * @param value The score value of the NomisScore.
     * @param chainId The chain id of the NomisScore.
     * @param calcModel The scoring calculation model of the NomisScore.
     * @param attester The attester address.
     */
    event Attestation(
        bytes32 indexed schema,
        uint64 expirationTime,
        uint256 tokenId,
        uint256 updated,
        uint16 value,
        uint256 chainId,
        uint16 calcModel,
        address indexed attester
    );

    /*#########################
    ##      Constructor      ##
    ##########################*/

    /**
     * @notice Contract constructor.
     * @param modules list of modules to use for the portal (can be empty).
     * @param router the Router's address.
     * @dev This sets the addresses for the AttestationRegistry, ModuleRegistry and PortalRegistry.
     */
    constructor(
        address[] memory modules,
        address router
    ) AbstractPortal(modules, router) {}

    /*#########################
    ##    Write Functions    ##
    ##########################*/

    /**
     * @dev Pauses the contract.
     * See {Pausable-_pause}.
     * Can only be called by the owner.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses the contract.
     * See {Pausable-_unpause}.
     * Can only be called by the owner.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Withdraws funds from the contract.
     * @param to the address to send the funds to.
     * @param amount the amount to withdraw.
     */
    function withdraw(
        address payable to,
        uint256 amount
    ) external override onlyOwner {
        (bool s, ) = to.call{ value: amount }("");
        if (!s) revert WithdrawFail();
    }

    /**
     * @notice Issues a Verax attestation based on NomisScore data.
     * @param schema The schema to attest.
     * @param expirationTime The expiration time of the attestation.
     * @param revocable Whether the attestation is revocable or not.
     * @param tokenId The token id of the minted NomisScore.
     * @param updated The timestamp of the mint or last update of the NomisScore.
     * @param value The score value of the NomisScore.
     * @param chainId The chain id of the NomisScore.
     * @param calcModel The scoring calculation model of the NomisScore.
     */
    function attestNomisScoreSimple(
        bytes32 schema,
        uint64 expirationTime,
        bool revocable,
        uint256 tokenId,
        uint256 updated,
        uint16 value,
        uint256 chainId,
        uint16 calcModel,
        bytes[] memory validationPayload
    ) public payable whenNotPaused {
        AttestationRequestData memory attestationRequestData = AttestationRequestData(
            expirationTime,
            revocable,
            tokenId,
            updated,
            value,
            chainId,
            calcModel
        );
        AttestationRequest memory attestationRequest = AttestationRequest(
            schema,
            attestationRequestData
        );
        attestNomisScore(attestationRequest, validationPayload);
    }

    /**
     * @notice Issues a Verax attestation based on NomisScore data.
     * @param attestationRequest The NomisScore payload to attest.
     * @param validationPayload The payload (for ex. signatures) to validate via the modules to issue the attestations.
     */
    function attestNomisScore(
        AttestationRequest memory attestationRequest,
        bytes[] memory validationPayload
    ) public payable whenNotPaused {
        if (attestationRequest.data.expirationTime < block.timestamp) {
            revert AttestationExpired();
        }

        bytes memory attestationData = abi.encode(
            attestationRequest.data.tokenId,
            attestationRequest.data.updated,
            attestationRequest.data.value,
            attestationRequest.data.chainId,
            attestationRequest.data.calcModel
        );
        AttestationPayload memory attestationPayload = AttestationPayload(
            attestationRequest.schema,
            attestationRequest.data.expirationTime,
            abi.encode(msg.sender),
            attestationData
        );
        super.attest(attestationPayload, validationPayload);

        emit Attestation(
            attestationRequest.schema,
            attestationRequest.data.expirationTime,
            attestationRequest.data.tokenId,
            attestationRequest.data.updated,
            attestationRequest.data.value,
            attestationRequest.data.chainId,
            attestationRequest.data.calcModel,
            msg.sender
        );
    }

    /**
     * @notice Issues Verax attestations in bulk, based on a list of EAS attestations.
     * @param attestationsRequests The NomisScore payloads to attest.
     * @param validationPayload The payload (for ex. signatures) to validate via the modules to issue the attestations.
     */
    function bulkAttestNomisScore(
        AttestationRequest[] memory attestationsRequests,
        bytes[] memory validationPayload
    ) external payable {
        for (uint256 i = 0; i < attestationsRequests.length; i++) {
            attestNomisScore(attestationsRequests[i], validationPayload);
        }
    }
}
