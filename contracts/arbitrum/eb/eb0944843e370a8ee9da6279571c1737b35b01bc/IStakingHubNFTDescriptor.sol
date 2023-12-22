// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;



/**
 * @title The interface for generating a description for a staking position in Staking Hub
 * @notice Contracts that implement this interface must return a base64 JSON with the entire description
 */

interface IStakingHubNFTDescriptor {
  /**
   * @notice Generates a staking position's description, both the JSON and the image inside
   * @param hub The address of the staking hub
   * @param stakingPositionId The id of the staking position
   * @return The URI of the ERC721-compliant metadata
   */
  function tokenURI(address hub, uint256 stakingPositionId) external view returns (string memory);
}
