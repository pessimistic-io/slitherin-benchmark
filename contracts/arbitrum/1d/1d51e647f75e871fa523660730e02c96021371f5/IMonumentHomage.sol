// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface IMonumentHomage {
  struct StakedMonument {
    uint256 tokenId;
    uint256 amount;
  }

  struct HomageDestination {
    uint256 realmId;
    uint256 structureId;
    uint256 structureAmount;
  }

  struct HomageRequest {
    address adventurerAddress;
    uint256 adventurerId;
    bytes32[] proofs;
    HomageDestination[] destinations;
  }

  function payHomage(HomageRequest[] calldata _requests) external;

  function getEligibleStructureAmounts(
    uint256[] calldata _realmIds,
    uint256[] calldata _tokenIds
  ) external view returns (uint256[] calldata);

  function getAdventurerHomagePoints(
    address[] calldata _addresses,
    uint256[] calldata _adventurerIds
  ) external view returns (uint256[] calldata);
}

