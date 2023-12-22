// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IProfileNFTEvents
 * @dev Interface for emitting events from the ProfileNFT contract
 */
interface IProfileNFTEvents {
  /**
   * @dev Emitted when the contract is initialized
   * @param owner The address that owns the contract
   * @param name The name of the contract
   * @param symbol The symbol of the contract
   */
  event Initialize(address indexed owner, string name, string symbol);

  /**
   * @dev Emitted when the verifier is changed
   * @param verifier The address of the new verifier
   * @param oldVerifier The address of the old verifier
   */
  event LogVerifierChanged(address indexed verifier, address oldVerifier);

  /**
   * @dev Emitted when the profile is minted
   * @param to The address of the profile owner
   * @param tokenId The token ID of the profile
   * @param handle The handle of the profile
   */
  event LogProfileMinted(
    address indexed to,
    uint256 indexed tokenId,
    string handle
  );
}

