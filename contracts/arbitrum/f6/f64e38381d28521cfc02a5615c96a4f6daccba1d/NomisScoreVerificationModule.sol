// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "./EIP712.sol";
import "./Ownable.sol";

import { AbstractModule } from "./AbstractModule.sol";
import { AttestationPayload } from "./Structs.sol";

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
 * @title NomisScore Verification Module
 * @author Nomis Labs
 * @notice This contract is a module, able to verify attestation data for attestations.
 * @custom:security-contact info@nomis.cc
 */
contract NomisScoreVerificationModule is 
    Ownable,
    EIP712,
    AbstractModule
{
    /*#########################
    ##        Mappings       ##
    ##########################*/

    /**
     * @dev A mapping of addresses to nonces for replay protection.
     */
    mapping(address => uint256) private _nonce;

    /*#########################
    ##      Constructor      ##
    ##########################*/

    /**
     * @dev Constructor for the NomisScoreModule contract.
     */
    constructor() EIP712("NMSSM", "0.1") {
    }

    /*#########################
    ##    Write Functions    ##
    ##########################*/

    /**
     * @inheritdoc AbstractModule
     * @notice If the attestation data is not expected, an error is thrown bu require().
     * @param _attestationPayload The attestation data.
     * @param _signature Additional data required for verification.
     * @param _txSender The transaction sender's address.
     */
    function run(
        AttestationPayload memory _attestationPayload,
        bytes memory _signature,
        address _txSender,
        uint256 /*_value*/
    ) public override {
        require(_txSender == abi.decode(_attestationPayload.subject, (address)), "run: Invalid subject");

        // Decode the attestation payload using abi.decode
        (uint256 tokenId, uint256 updated, uint16 value, uint256 chainId, uint16 calcModel) = decodeAttestationData(_attestationPayload.attestationData);
        require(tokenId != 0 && updated != 0 && value != 0 && chainId != 0 && calcModel != 0, "run: Invalid attestation data");

        // Verify the signer of the message
        bytes32 messageHash = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256(
                        "VeraxAttestationMessage(uint256 tokenId,uint256 updated,uint16 value,uint256 chainId,uint16 calcModel,uint256 nonce,address to)"
                    ),
                    tokenId,
                    updated,
                    value,
                    chainId,
                    calcModel,
                    _nonce[_txSender]++,
                    _txSender
                )
            )
        );

        address signer = ECDSA.recover(messageHash, _signature);
        require(
            signer == owner() && signer != address(0),
            "run: Invalid signature"
        );
    }

    /*#########################
    ##    Read Functions    ##
    ##########################*/

    /**
     * @dev Returns the attestation data.
     * @param _attestationData The attestation data.
     * @return tokenId The token id of the minted NomisScore.
     * @return updated The timestamp of the mint or last update of the NomisScore.
     * @return value The score value of the NomisScore.
     * @return chainId The chain id of the NomisScore.
     * @return calcModel The scoring calculation model of the NomisScore.
     */
    function decodeAttestationData(
        bytes memory _attestationData
    ) public pure returns (
        uint256 tokenId,
        uint256 updated,
        uint16 value,
        uint256 chainId,
        uint16 calcModel
    ) {
        return abi.decode(_attestationData, (uint256, uint256, uint16, uint256, uint16));
    }

    /**
     * @dev Returns the decoded subject of the attestation.
     * @param _subject The subject of the attestation.
     * @return to The decoded address.
     */
    function decodeSubject(
        bytes memory _subject
    ) public pure returns (
        address to
    ) {
        return abi.decode(_subject, (address));
    }

    /**
     * @dev Check the signature of the attestation data.
     * @param _attestationData The attestation data.
     * @param _txSender The transaction sender's address.
     * @param _signature the signature required for verification.
     */
    function checkSignature(
        bytes memory _attestationData,
        address _txSender,
        bytes memory _signature
    ) public view returns (
        uint256 tokenId,
        uint256 updated,
        uint16 value,
        uint256 chainId,
        uint16 calcModel,
        address signer,
        bool success
    ) {
        // Decode the attestation payload using abi.decode
        (tokenId, updated, value, chainId, calcModel) = decodeAttestationData(_attestationData);

        // Verify the signer of the message
        bytes32 messageHash = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256(
                        "VeraxAttestationMessage(uint256 tokenId,uint256 updated,uint16 value,uint256 chainId,uint16 calcModel,uint256 nonce,address to)"
                    ),
                    tokenId,
                    updated,
                    value,
                    chainId,
                    calcModel,
                    _nonce[_txSender],
                    _txSender
                )
            )
        );

        signer = ECDSA.recover(messageHash, _signature);
        success = signer == owner() && signer != address(0);
    }

    /**
     * @dev Returns the nonce value for the calling address.
     * @param addr The address to get the nonce for.
     * @return The nonce value for the calling address.
     */
    function getNonce(address addr) external view returns (uint256) {
        return _nonce[addr];
    }
}
