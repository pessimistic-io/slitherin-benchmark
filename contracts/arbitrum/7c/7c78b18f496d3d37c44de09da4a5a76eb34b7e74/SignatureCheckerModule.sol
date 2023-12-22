// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { AbstractModule } from "./AbstractModule.sol";
import { AttestationPayload } from "./Structs.sol";
import { Ownable } from "./Ownable.sol";
import { ECDSA } from "./ECDSA.sol";

/**
 * @title SignatureChecker Module
 * @author Clique
 * @notice This contract is an example of a module,
 *         able to verify signed data against an address
 */
contract SignatureCheckerModule is Ownable, AbstractModule {
  using ECDSA for bytes32;

  mapping(address signer => bool authorizedSigners) public authorizedSigners;

  /// @notice Error thrown when an array length mismatch occurs
  error ArrayLengthMismatch();
  /// @notice Error thrown when a signer is not authorized by the module
  error SignerNotAuthorized();

  /**
   * @notice Set the accepted status of schemaIds
   * @param signers The signers to be set
   * @param authorizationStatus The authorization status of signers
   */
  function setAuthorizedSigners(address[] memory signers, bool[] memory authorizationStatus) public onlyOwner {
    if (signers.length != authorizationStatus.length) revert ArrayLengthMismatch();

    for (uint256 i = 0; i < signers.length; i++) {
      authorizedSigners[signers[i]] = authorizationStatus[i];
    }
  }

  /**
   * @notice The main method for the module, running the check
   * @param _attestationPayload The Payload of the attestation
   * @param _validationPayload The validation payload required for the module
   */
  function run(
    AttestationPayload memory _attestationPayload,
    bytes memory _validationPayload,
    address /*_txSender*/,
    uint256 /*_value*/
  ) public view override {
    bytes32 messageHash = keccak256(abi.encode(_attestationPayload));
    address messageSigner = messageHash.toEthSignedMessageHash().recover(_validationPayload);
    if (!authorizedSigners[messageSigner]) revert SignerNotAuthorized();
  }
}

