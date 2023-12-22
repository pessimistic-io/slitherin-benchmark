// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IVerifierProxy {
  /**
   * @notice Verifies that the data encoded has been signed
   * correctly by routing to the correct verifier, and bills the user if applicable.
   * @param payload The encoded data to be verified, including the signed
   * report and any metadata for billing.
   * @return verifierResponse The encoded report from the verifier.
   */
  function verify(bytes calldata payload) external payable returns (bytes memory verifierResponse);
}
