// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { AbstractModule } from "./AbstractModule.sol";
import { AttestationPayload } from "./Structs.sol";
import { Ownable } from "./Ownable.sol";

/**
 * @title Payable Module
 * @author Clique
 * @notice This contract is an example of a module, able to charge a fee for attestations
 */
contract PayableModule is Ownable, AbstractModule {
  mapping(bytes32 schemaId => uint256 attestationFee) public attestationFees;

  /// @notice Error thrown when an array length mismatch occurs
  error ArrayLengthMismatch();
  /// @notice Error thrown when an invalid attestation fee is provided
  error InvalidAttestationFee();

  /**
   * @notice Set the fee required to attest
   * @param _attestationFees The fees required to attest
   * @param schemaIds The schemaIds to set the fee for
   */
  function setFees(bytes32[] memory schemaIds, uint256[] memory _attestationFees) public onlyOwner {
    if (schemaIds.length != _attestationFees.length) revert ArrayLengthMismatch();

    for (uint256 i = 0; i < schemaIds.length; i++) {
      attestationFees[schemaIds[i]] = _attestationFees[i];
    }
  }

  /**
   * @notice The main method for the module, running the check
   * @param _value The value sent for the attestation
   */
  function run(
    AttestationPayload memory _attestationPayload,
    bytes memory /*_validationPayload*/,
    address /*_txSender*/,
    uint256 _value
  ) public view override {
    uint256 attestationFee = attestationFees[_attestationPayload.schemaId];
    if (_value < attestationFee) revert InvalidAttestationFee();
  }
}

