// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { AbstractModule } from "./AbstractModule.sol";
import { AttestationPayload } from "./Structs.sol";
import { Ownable } from "./Ownable.sol";

/**
 * @title SchemaChecker Module
 * @author Clique
 * @notice This contract is an example of a module,
 *         able to check for accepted schemaIds
 */
contract SchemaCheckerModule is Ownable, AbstractModule {
  mapping(bytes32 schemaId => bool accepted) public acceptedSchemaIds;

  /// @notice Error thrown when an array length mismatch occurs
  error ArraylengthMismatch();
  /// @notice Error thrown when a schemaId is not accepted by the module
  error SchemaIdNotAccepted();

  /**
   * @notice Set the accepted status of schemaIds
   * @param schemaIds The schemaIds to be set
   * @param acceptedStatus The accepted status of schemaIds
   */
  function setAcceptedSchemaIds(bytes32[] memory schemaIds, bool[] memory acceptedStatus) public onlyOwner {
    if (schemaIds.length != acceptedStatus.length) revert ArraylengthMismatch();

    for (uint256 i = 0; i < schemaIds.length; i++) {
      acceptedSchemaIds[schemaIds[i]] = acceptedStatus[i];
    }
  }

  /**
   * @notice The main method for the module, running the check
   * @param _attestationPayload The Payload of the attestation The value sent for the attestation
   */
  function run(
    AttestationPayload memory _attestationPayload,
    bytes memory /*_validationPayload*/,
    address /*_txSender*/,
    uint256 /*_value*/
  ) public view override {
    if (!acceptedSchemaIds[_attestationPayload.schemaId]) revert SchemaIdNotAccepted();
  }
}

